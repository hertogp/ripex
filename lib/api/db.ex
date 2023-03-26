defmodule Ripe.API.DB do
  @moduledoc """
  This module contains functions to:
  = [lookup](https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html#rest-api-lookup) RIPE database objects
  - [search](https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html#rest-api-search) the RIPE database
  - get a [template](https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html#metadata-object-template) for a specified object.

  See
  - [REST API Lookup](https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html)
  - [database structure](https://apps.db.ripe.net/docs/03.RIPE-Database-Structure/01-Database-Object.html)
  - [object types](https://apps.db.ripe.net/docs/04.RPSL-Object-Types/#rpsl-object-types)
      - [primary objects](https://apps.db.ripe.net/docs/04.RPSL-Object-Types/02-Descriptions-of-Primary-Objects.html#descriptions-of-primary-objects)
      - [secondary objects](https://apps.db.ripe.net/docs/04.RPSL-Object-Types/03-Descriptions-of-Secondary-Objects.html#descriptions-of-secondary-objects)

  """

  alias Ripe.API

  # @db_lookup_url "https://rest.db.ripe.net/ripe"
  @db_template_url "https://rest.db.ripe.net/metadata/templates"
  @db_search_url "https://rest.db.ripe.net/search.json?"

  # Helpers

  def collect_keys_byvalue(map, fun) when is_map(map) do
    # collect keys by value using given `fun`
    for {k, m} <- map, fun.(m), into: [] do
      k
    end
    |> Enum.filter(fn k -> k end)
  end

  def collect_values_bykey(list, key, valkey) when is_list(list) do
    list
    |> Enum.filter(fn m -> Map.has_key?(m, key) end)
    |> Enum.reduce(%{}, fn map, acc ->
      k = Map.get(map, key)
      v = Map.get(acc, k, [])
      Map.put(acc, k, v ++ [map[valkey]])
    end)
  end

  defp decode(%{http: 200, source: :"Ripe.API.DB.lookup"} = result) do
    # lookup returns only one object
    data_path = [:body, "objects", "object", 0]

    obj =
      result
      |> API.get_at(data_path)
      |> decode_obj()

    result
    |> Map.put(:version, API.get_at(result, [:body, "version", "version"]))
    |> Map.merge(obj)
    |> Map.delete(:body)
  end

  defp decode(%{http: 200, source: :"Ripe.API.DB.search"} = result) do
    # search returns one or more objects
    data_path = [:body, "objects", "object"]

    objects =
      result
      |> API.get_at(data_path)
      |> Enum.reduce([], fn obj, acc -> [decode_obj(obj) | acc] end)
      |> IO.inspect(label: :objects)
      |> Enum.reverse()

    result
    |> Map.put(:objects, objects)
    |> Map.delete(:body)
  end

  defp decode(%{http: 200, source: :"Ripe.API.DB.template"} = result) do
    # template returns only one object in its own formatt
    data_path = [:body, "templates", "template", 0]

    attrs =
      result
      |> API.get_at(data_path ++ ["attributes", "attribute"])
      |> API.map_bykey("name")

    result
    |> Map.put(:rir, API.get_at(result, data_path ++ ["source"])["id"])
    |> Map.put(:type, API.get_at(result, data_path ++ ["type"]))
    |> Map.put(
      :primary_keys,
      collect_keys_byvalue(attrs, fn m -> "PRIMARY_KEY" in Map.get(m, "keys", []) end)
    )
    |> Map.put(
      :inverse_keys,
      collect_keys_byvalue(attrs, fn m -> "INVERSE_KEY" in Map.get(m, "keys", []) end)
    )
    |> Map.put(
      :lookup_keys,
      collect_keys_byvalue(attrs, fn m -> "LOOKUP_KEY" in Map.get(m, "keys", []) end)
    )
    |> Map.delete(:body)
    |> Map.merge(attrs)
  end

  defp decode(%{source: :"Ripe.API.DB.lookup"} = result) do
    # not a http: 200 -> error
    reason =
      result
      |> API.get_at([:body, "errormessages", "errormessage"])
      |> Enum.map(fn map -> map["text"] end)
      |> Enum.join("\n")

    result
    |> Map.put(:erorr, reason)
    |> Map.delete(:body)
  end

  defp decode(%{source: :"Ripe.API.DB.search"} = result) do
    # not a http: 200 -> error
    reason =
      result
      |> API.get_at([:body, "errormessages", "errormessage"])
      |> Enum.map(fn map -> {map["text"], Enum.map(map["args"], fn m -> m["value"] end)} end)
      |> Enum.map(fn {msg, args} ->
        Enum.reduce(args, msg, fn val, acc ->
          String.replace(acc, "%s", "#{val}")
        end)
      end)
      |> Enum.join()

    result
    |> Map.put(:error, reason)
    |> Map.delete(:body)
  end

  defp decode(%{source: :"Ripe.API.DB.template"} = result) do
    # not a http: 200 -> error
    result
    |> Map.put(:error, result[:body]["message"])
    |> Map.delete(:body)
  end

  defp decode_obj(obj) do
    # decode a single object
    attrs =
      obj
      |> IO.inspect(label: :object)
      |> API.get_at(["attributes", "attribute"])
      |> collect_values_bykey("name", "value")

    primary_key =
      obj
      |> API.get_at(["primary-key", "attribute"])
      |> Enum.reduce("", fn m, acc -> acc <> m["value"] end)

    obj
    |> Map.merge(attrs)
    |> Map.put(:primary_key, primary_key)
    |> Map.delete("attributes")
    |> Map.delete("primary-key")
    |> Map.delete("link")
  end

  # API

  @doc """
  Retrieve a single object for given `object`-type and search `keys`.

  The `object` specifies the name of either a
  [primary](https://apps.db.ripe.net/docs/04.RPSL-Object-Types/02-Descriptions-of-Primary-Objects.html)
  or a
  [secondary](https://apps.db.ripe.net/docs/04.RPSL-Object-Types/03-Descriptions-of-Secondary-Objects.html)
  object.

  The list of `keys` consists of one or more string values that make up the
  primary key of the object to retrieve.

  The options in `opts` may include
  - `unfiltered: true`, so notify- and email-attributes are not filtered out (default `false`)
  - `unformatted: true`, in which case the attribute values contain their original formatting.
  - `:timeout number`, where number defaults to 2000 ms.

  See
  -[Ripe Lookup](https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html#rest-api-lookup)


  """
  def lookup(object, keys, opts \\ []) do
    key = Enum.join(keys)
    opts = [opts: [recv_timeout: Keyword.get(opts, :timeout, 2_000)]]

    flags =
      [
        Keyword.get(opts, :unfiltered, false) && "unfiltered",
        Keyword.get(opts, :unformatted, false) && "unformatted"
      ]
      |> Enum.filter(fn x -> x end)
      |> Enum.join("&")

    "https://rest.db.ripe.net/ripe/#{object}/#{key}.json?#{flags}"
    |> String.replace_suffix("?", "")
    |> API.fetch(opts)
    |> Map.put(:source, :"Ripe.API.DB.lookup")
    |> decode()
    |> Map.put(:type, object)
  end

  @doc """
  Retrieve one or more objects via [Ripe
    Search](https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html#rest-api-search).

  The `query` parameter specifies the string value to search for.  By default this will find objects
  whose primary key matches or have a lookup key that (partially) matches.

  See also:
  - [primary vs lookup keys](https://apps.db.ripe.net/docs/13.Types-of-Queries/01-Queries-Using-Primary-and-Lookup-Keys.html#queries-using-primary-and-lookup-keys)
  - [what is returned](https://apps.db.ripe.net/docs/16.Tables-of-Query-Types-Supported-by-the-RIPE-Database/#table-1-queries-using-primary-and-lookup-keys)

  Use `params` to list additional [query
    parameters](https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html#uri-query-parameters)
  in the form of `[{"name", ["value", ...]}, ..]` as needed.  They include:

  - `"source":`, the name or list of names of the sources to be searched
  - `"inverse-attribute":`,  the name or list of names of inverse indexed attributes to search
  - `"include-tag":`, name or list of names of tags that RPSL objects must have
  - `"exclude-tag":`, name or list of names of tags that RPSL objects cannot have
  - `"type-filter":`, type or list of types the returned objects must have
  - `"flags":`, a flag or list of flags to influence the search behaviour (see below)
  - `"unformatted":`, if true, attribute values maintain their original formatting
  - `"managed-attributes":`, if true, adds a "managed" field to objects if they are (also) managed by RIPE
  - `"resource-holder":`, if true, include resource holder organisation (id and name)
  - `"abuse-contact":`, if true, include abuse-c email of the resource (if any)
  - `"limit"`, max nr of RPSL obj's to return in the response
  - `"offset"`, return RPSL obj's from a specified offset

  See [flags](https://apps.db.ripe.net/docs/16.Tables-of-Query-Types-Supported-by-the-RIPE-Database) for
  more information on how to use them and in what type of queries.

  Some of the interesting `flags` include:

  - `B`, unfiltered
  - `k`, persistent connectin
  - `G`, turn grouping off
  - `M`, (all-more) include all more specific matches
  - `m`, (one-more) include 1-level more specific
  - `L`, (all-less) include less specific matches
  - `l`, (one-less) include 1-level less specific
  - `x`, (exact)  exact match (domain objects)
  - `r`, (no-referenced) turns off retrieving additional contact information


  ## Examples

  - find all more specific inetnum and route objects for a given prefix:
      - query=<prefix>
      - params = [{"flags", ["M", "B"]}]

  """
  def search(query, opts \\ []) do
    db_search = "https://rest.db.ripe.net/search.json?"

    flags =
      opts
      |> Keyword.filter(fn {_k, v} -> v == true end)
      |> Enum.map(fn {k, _v} -> k end)

    params =
      opts
      |> Keyword.drop([:timeout])
      |> Keyword.drop(flags)
      |> Enum.map(fn {k, v} -> {String.replace("#{k}", "_", "-", global: true), List.wrap(v)} end)
      |> Enum.map(fn {k, l} -> for v <- l, do: "#{k}=#{v}" end)
      |> List.flatten()
      |> Kernel.++(flags)
      |> Enum.join("&")

    timeout = [opts: [recv_timeout: Keyword.get(opts, :timeout, 2_000)]]

    "#{db_search}#{params}&query-string=#{query}"
    |> API.fetch(timeout)
    |> Map.put(:source, :"Ripe.API.DB.search")
    |> Map.put(:query, "#{query}")
    |> decode()
  end

  @doc """
  Retrieve a template for given `object`-type.

  Each template fetched will be decoded into a map and cached.

  See:
  - [Ripe Template](https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html#metadata-object-template)
  - https://apps.db.ripe.net/docs/03.RIPE-Database-Structure/01-Database-Object.html
  - [RPSL object types](https://apps.db.ripe.net/docs/04.RPSL-Object-Types/)

  Notes:
  - attribute names consist of alphanumeric characters plus hyphens
  - attributes names are case-insensitive, RIPE DB converts them to lowercase
  """
  def template(object) do
    "#{@db_template_url}/#{object}.json"
    |> API.fetch()
    |> Map.put(:source, :"Ripe.API.DB.template")
    |> Map.put(:type, "#{object}")
    |> decode()
  end

  # Helpers
end
