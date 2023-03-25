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

  @db_lookup_url "https://rest.db.ripe.net/ripe"
  @db_template_url "https://rest.db.ripe.net/metadata/templates"
  @db_search_url "https://rest.db.ripe.net/search.json?"

  # DECODE helpers

  defp decode(%{http: 200, source: :"Ripe.API.DB.lookup"} = result) do
    # Lookup returns only one object
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
    # template return only one object in its own formatt
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
    result
    |> Map.put(:error, result[:body]["message"])
    |> Map.delete(:body)
  end

  defp decode_obj(obj) do
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
  Retrieve a single object for given `object`-type, search `keys` optionally using `flags`.

  The result is a map with atom-keys providing API information and string keys for the information
  items retrieved through the API call.

  See
  -[Ripe Lookup](https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html#rest-api-lookup)


  """
  def lookup(object, keys, flags \\ []) do
    keyz = Enum.join(keys)
    flagz = Enum.join(flags, "&")

    "https://rest.db.ripe.net/ripe/#{object}/#{keyz}.json?#{flagz}"
    |> String.replace_prefix("?", "")
    |> API.fetch()
    |> Map.put(:source, :"Ripe.API.DB.lookup")
    |> decode()
    |> Map.put(:type, object)
  end

  @doc """
  Retrieve a template for given `object`-type.

  Each template fetched will be decoded into a map and cached.

  See:
  - https://apps.db.ripe.net/docs/03.RIPE-Database-Structure/01-Database-Object.html
  - https://apps.db.ripe.net/docs/04.RPSL-Object-Types/

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

  @doc """
  See [Ripe Search](https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html#rest-api-search).

  - `query` is the mandatory query-string being search for
  - `params` is a list of [{"name", ["values"]}]
  """
  def search(query, params \\ []) do
    qparams =
      params
      |> IO.inspect(label: :params)
      |> Enum.reduce([], fn {name, vals}, acc ->
        acc ++ Enum.reduce(vals, [], fn val, acc -> ["#{name}=#{val}" | acc] end)
      end)
      |> Enum.join("&")

    "#{@db_search_url}#{qparams}&query-string=#{query}"
    |> API.fetch()
    |> IO.inspect()
    |> Map.put(:source, :"Ripe.API.DB.search")
    |> Map.put(:query, "#{query}")
    |> decode()
  end

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
end
