defmodule Ripe.API.DB do
  @moduledoc """
  This module implements some of the [RESTful
    API](https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html)'s
  of the [RIPE NCC database](https://apps.db.ripe.net/docs/) to retrieve its
  [objects](https://apps.db.ripe.net/docs/04.RPSL-Object-Types/#rpsl-object-types).


  - [abuse-contact](https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html#rest-api-abuse-contact),
    retrieve abuse contact information if available.
  - [lookup](https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html#rest-api-lookup),
    retrieve a single object form the RIPE database.
  - [search](https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html#rest-api-search),
    retrieve one or more objects from the RIPE database
  - [template](https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html#metadata-object-template),
    retrieve a single template for a specified object type..

  """

  alias Ripe.API

  @db_abuse_c "https://rest.db.ripe.net/abuse-contact"
  @db_lookup "https://rest.db.ripe.net/ripe"
  @db_template "https://rest.db.ripe.net/metadata/templates"
  @db_search "https://rest.db.ripe.net/search.json?"

  # [[ TODO: ]]
  # - add https://rest.db.ripe.net/abuse-contact/{resource}
  # - add subAPI https://ipmap.ripe.net/ (since rest.db.ripe.net/geolocation doesn't work anymore)
  #   `-> see https://ipmap.ripe.net/docs/02.api-reference/
  # - add flags: "r" by default to help avoid retrieving too much personal data (and get blocked)
  # - use the TEST database, but how?  Nothting seems to work and documentation is out of date it seems.
  #
  # GRS=Global Resource Service, one of: RIPE, RADb, APNIC, ARIN, AfriNIC, LACNIC

  # [[ HELPERS ]]

  defp collect_keys_byvalue(map, fun) when is_map(map) do
    # collect keys by value using given `fun`
    for {k, m} <- map, fun.(m), into: [] do
      k
    end
    |> Enum.filter(fn k -> k end)
  end

  defp collect_values_bykey(list, key, valkey) when is_list(list) do
    list
    |> Enum.filter(fn m -> Map.has_key?(m, key) end)
    |> Enum.reduce(%{}, fn map, acc ->
      k = Map.get(map, key)
      v = Map.get(acc, k, [])
      Map.put(acc, k, v ++ [map[valkey]])
    end)
  end

  @spec decode(map) :: map
  defp decode(%{http: 200, source: "Ripe.API.DB.abuse_c"} = result) do
    # abuse_c doesn't really return an RPSL object
    data_path = [:body, "abuse-contacts"]

    obj =
      result
      |> API.get_at(data_path)

    primary_key =
      result
      |> API.get_at([:body, "parameters", "primary-key", "value"])

    result
    |> Map.merge(obj)
    |> Map.put(:primary_key, primary_key)
    |> Map.delete(:body)
  end

  defp decode(%{http: 200, source: "Ripe.API.DB.lookup"} = result) do
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

  defp decode(%{http: 200, source: "Ripe.API.DB.search"} = result) do
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
    |> Map.put(:version, API.get_at(result, [:body, "version", "version"]))
    |> Map.delete(:body)
  end

  defp decode(%{http: 200, source: "Ripe.API.DB.template"} = result) do
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

  defp decode(%{source: "Ripe.API.DB.abuse_c"} = result) do
    # not a http: 200 -> error, 301 is redirect with empty body (redirect
    # contains the error messages)
    result
    |> API.get_at([:body, "message"])
    |> then(fn msg -> Map.put(result, :error, msg) end)
    |> Map.delete(:body)
  end

  defp decode(%{source: "Ripe.API.DB.lookup"} = result) do
    # not a http: 200 -> error, 301 is redirect with empty body (redirect
    # contains the error messages)
    result
    |> Map.put(:error, decode_err(result))
    |> Map.delete(:body)
  end

  defp decode(%{source: "Ripe.API.DB.search"} = result) do
    # not a http: 200 -> error

    result
    |> Map.put(:error, decode_err(result))
    |> Map.delete(:body)
  end

  defp decode(%{source: "Ripe.API.DB.template"} = result) do
    # not a http: 200 -> error
    result
    |> Map.put(:error, result[:body]["message"])
    |> Map.delete(:body)
  end

  @spec decode_err(map) :: binary
  defp decode_err(obj) do
    obj
    |> API.get_at([:body, "errormessages", "errormessage"], %{"text" => "unknown error"})
    |> Enum.map(fn map -> {map["text"], Enum.map(map["args"] || [], fn m -> m["value"] end)} end)
    |> Enum.map(fn {msg, args} ->
      Enum.reduce(args, msg, fn val, acc ->
        String.replace(acc, "%s", "#{val}")
      end)
    end)
    |> Enum.join()
  end

  @spec decode_obj(map) :: map
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

  # [[ API ]]

  @doc """
  Retrieve [abuse-contact](https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html#rest-api-abuse-contact)
  information, if possible, for given `key`.

  where:
  - `key` is either an ASnr, IP Prefix or an IP address.
  - `opts` may include a `timeout: N`, where N is the timeout in ms (default 2000).

  Upon success, a map is returned with keys:
  - `:http`, 200,
  - `:method`, :get,
  - `:opts`, options given to the http client
  - `:primary_key`, primary key for object found,
  - `:source`, "Ripe.API.DB.abuse_c",
  - `:url`, the url used to retrieve the information
  - `"email"`, "some email address",
  - `"key"`, "nic-handle of role or person",
  - `"org-id"`,  "nic-handle of organisation",
  - `"suspect"`, false (or true :)

  Upon failure, a map is returned with keys:
  - `error:`, "some reason",
  - `http:`, 400,
  - `method:`, :get,
  - `opts:`, options given to the http client
  - `source:` "Ripe.API.DB.abuse_c",
  - `url:` "the url that was used"

  Note that even if the call returns successful, there might not be any contact
  information available (i.e. it doesn't return a 404).

  ## Examples

  Abuse contact for an ASnr:

      iex> abuse_c("AS3333")
      %{
        :http => 200,
        :method => :get,
        :opts => [recv_timeout: 2000],
        :primary_key => "AS3333",
        :source => "Ripe.API.DB.abuse_c",
        :url => "https://rest.db.ripe.net/abuse-contact/AS3333.json",
        "email" => "abuse@ripe.net",
        "key" => "OPS4-RIPE",
        "org-id" => "ORG-RIEN1-RIPE",
        "suspect" => false
      }

  No contact information found for an IPv4 address, but it does not return a 404.

      iex> abuse_c("1.1.1.1")
      %{
        :http => 200,
        :method => :get,
        :opts => [recv_timeout: 2000],
        :primary_key => "0.0.0.0 - 1.178.111.255",
        :source => "Ripe.API.DB.abuse_c",
        :url => "https://rest.db.ripe.net/abuse-contact/1.1.1.1.json",
        "email" => "",
        "key" => "",
        "org-id" => "",
        "suspect" => false
      }

  An error due to an invalid `key`.

      iex> abuse_c("1.1.1.x")
      %{
        error: "Invalid argument: 1.1.1.x",
        http: 400,
        method: :get,
        opts: [recv_timeout: 2000],
        source: "Ripe.API.DB.abuse_c",
        url: "https://rest.db.ripe.net/abuse-contact/1.1.1.x.json"
      }

  Weirdly enough, using an IPv6 address apparently does yield a 404 when there
  is nog contract information available.

      iex(339)> Ripe.API.DB.abuse_c("::1.1.1.1")
      %{
        error: "No abuse contact found for ::1.1.1.1",
        http: 404,
        method: :get,
        opts: [recv_timeout: 2000],
        source: "Ripe.API.DB.abuse_c",
        url: "https://rest.db.ripe.net/abuse-contact/::1.1.1.1.json"
      }
  """
  @spec abuse_c(binary, Keyword.t()) :: map
  def abuse_c(key, opts \\ []) do
    # db_lookup = "https://rest.db.ripe.net/ripe"
    opts = [opts: [recv_timeout: Keyword.get(opts, :timeout, 2_000)]]

    "#{@db_abuse_c}/#{key}.json"
    |> API.fetch(opts)
    |> IO.inspect()
    |> Map.put(:source, "Ripe.API.DB.abuse_c")
    |> decode()
  end

  @doc """
  [lookup](https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html#rest-api-lookup)
  a single object of given `object`-type using given `key` in the RIPE NCC database.

  The `object` specifies the name of either a
  [primary](https://apps.db.ripe.net/docs/04.RPSL-Object-Types/02-Descriptions-of-Primary-Objects.html),
  or a
  [secondary](https://apps.db.ripe.net/docs/04.RPSL-Object-Types/03-Descriptions-of-Secondary-Objects.html)
  object.

  The `key` is the objects' *primary* key as a binary. Note that some objects,
  like e.g.
  [route](https://apps.db.ripe.net/docs/04.RPSL-Object-Types/02-Descriptions-of-Primary-Objects.html#description-of-the-route-object),
  have multiple attributes listed as a (mandatory) primary key, in which case
  you'll need to join the strings together in the order as they are listed in
  the objects' template. So for a route object those attributes are `route`
  and `origin`, so a key may look like "193.0.0.0/21AS3333".

  `opts` may include
  - `unfiltered: true`, so notify- and email-attributes are not filtered out (default `false`)
  - `unformatted: true`, in which case the attribute values retain their original formatting.
  - `timeout: N`, where `N` defaults to 2000 ms.

  When successful, a map is returned with some atom keys provided by this API client, and string
  keys for the attributes returned by RIPE, like:

  ```elixir
  %{
    http: 200,
    method: :get,
    opts: [recv_timeout: 2000],
    query: "193.0.0.0/21AS3333",
    source: "Ripe.API.DB.lookup",
    url: "url for the db lookup endpoint",
    version: "x.y",
    "some-attr": ["some values"]
  }
  ```

  In case of an error, the `http` code will not be `200` and the map will have
  an error field with some reason.

  """
  @spec lookup(binary, binary, Keyword.t()) :: map
  def lookup(object, key, opts \\ []) do
    # db_lookup = "https://rest.db.ripe.net/ripe"
    opts = [opts: [recv_timeout: Keyword.get(opts, :timeout, 2_000)]]

    flags =
      [
        Keyword.get(opts, :unfiltered, false) && "unfiltered",
        Keyword.get(opts, :unformatted, false) && "unformatted"
      ]
      |> Enum.filter(fn x -> x end)
      |> Enum.join("&")

    "#{@db_lookup}/#{object}/#{key}.json?#{flags}"
    |> String.replace_suffix("?", "")
    |> API.fetch(opts)
    |> IO.inspect()
    |> Map.put(:source, "Ripe.API.DB.lookup")
    |> Map.put(:type, object)
    |> decode()
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

  - `source:`, the name or list of names of the sources to be searched
  - `"inverse-attribute":`,  the name or list of names of inverse indexed attributes to search
  - `"include-tag":`, name or list of names of tags that RPSL objects must have
  - `"exclude-tag":`, name or list of names of tags that RPSL objects cannot have
  - `"type-filter":`, type or list of types the returned objects must have
  - `flags:`, a flag or list of flags to influence the search behaviour (see below)
  - `unformatted:`, if true, attribute values maintain their original formatting
  - `"managed-attributes":`, if true, adds a RIPE "managed" boolean field to objects
  - `"resource-holder":`, if true, include resource holder organisation (id and name)
  - `"abuse-contact":`, if true, include abuse-c email of the resource (if any)
  - `limit:`, max nr of RPSL obj's to return in the response
  - `offset:`, return RPSL obj's from a specified offset

  See [flags](https://apps.db.ripe.net/docs/16.Tables-of-Query-Types-Supported-by-the-RIPE-Database) for
  more information on how to use them and in what type of queries.

  Some of the interesting `flags` include:

  - `B`, unfiltered
  - `k`, persistent connection
  - `G`, turn grouping off
  - `M`, (all-more) include all more specific matches
  - `m`, (one-more) include 1-level more specific
  - `L`, (all-less) include less specific matches
  - `l`, (one-less) include 1-level less specific
  - `x`, (exact)  exact match (domain objects)
  - `r`, (no-referenced) turns off retrieving additional contact information

  Adding the `flags: "r"` will help prevent exceeding the [Fair Use
    Policy](https://www.ripe.net/manage-ips-and-asns/db/support/documentation/ripe-database-acceptable-use-policy),
  especially when looking for more specific objects for a large prefix since there is a limit on the
  amount of contact information you can retrieve in a day.

  ## Examples

  - `search("as3333", "inverse-attribute": "origin")`
    - find all route(6) objects whose origin matches as3333

  - `search("RIPE-NCC-MNT", "inverse-attribute": "mnt-by", flags: "r", "type-filter": "domain")`
    - find all domains maintained by RIPE-NCC-MNT, without any additional contact information

  - `search("RIPE-NCC-MNT", "inverse-attribute": "mnt-by", "type-filter": ["inetnum", "inet6num"], flags: "r")`
    - find all inet(6)num's maintained by RIPE-NCC-MNT, without additional contact information

  """
  def search(query, opts \\ []) do
    # TODO: URI encode the url so you can look for "first lastname"
    # db_search = "https://rest.db.ripe.net/search.json?"

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

    "#{@db_search}#{params}&query-string=#{query}"
    |> API.fetch(timeout)
    |> Map.put(:source, "Ripe.API.DB.search")
    |> Map.put(:query, "#{query}")
    |> decode()
  end

  @doc """
  Retrieve a template for given `object`-type.

  `opts` may include:
  - `timeout: N`, where N is the desired timeout in ms (default 2000)

  Upon success, a map is returned with keys:
  - `:http`, 200
  - `:method`, `:get`
  - `:opts`, any options given to the http client
  - `:source`, "Ripe.API.DB.template"
  - `:url`, the url used
  - `:type`, the given `object` type
  - `:rir`, usually "ripe"
  - `:primary_keys`, list of attribute names that, together, form the primary key
  - `:lookup_keys`, list of attribute names usable for normal lookup query
  - `:inverse_keys`, list of attribute names usable for an inverse query

  and a number of binary keys provided by RIPE that are the attribute names, which
  each point to a map describing the attribute
  [properties](https://apps.db.ripe.net/docs/03.RIPE-Database-Structure/09-Attribute-Properties.html#attribute-properties)

  ```
  %{
    :idx => N,
    "cardinality" => one of: "SINGLE" | "MULTIPLE",
    "requirement" => one of: "MANDATORY" | "OPTIONAL" | "REQUIRED" | "GENERATED"
    "keys" => subset of ["PRIMARY_KEY", "INVERSE_KEY", "LOOKUP_KEY"] (if at all present)
  }
  ```

  If an attribute is not (part of) a primary key and is not in the lookup- nor
  the inverse index then "keys" will not be present in the attribute map.  Note
  that the template's map already has keys that list the attribute names used
  for a primary key, a regular lookup key or as an inverse lookup key.

  Since the order in which attributes are listed in a template is imported, the
  value under key `:idx` specifies it was the `nth` attribute seen.

  In case of an error, a map is returned with keys:
  - `:http`, usually 404
  - `:error`, with some message
  - `:method`, `:get`
  - `:opts`, any options given to the http client
  - `:source`, "Ripe.API.DB.template"
  - `:type`, the given object type (which was not found)
  - `:url`, the url used

  See:
  - [Attribute properties](https://apps.db.ripe.net/docs/03.RIPE-Database-Structure/09-Attribute-Properties.html#attribute-properties)
  - [RPSL object types](https://apps.db.ripe.net/docs/04.RPSL-Object-Types/)
  - [Ripe Template](https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html#metadata-object-template)
  - [Ripe Db Objects](https://apps.db.ripe.net/docs/03.RIPE-Database-Structure/01-Database-Object.html)

  Notes:
  - attribute names consist of alphanumeric characters plus hyphens
  - attributes names are case-insensitive, RIPE DB converts them to lowercase
  - the order of attributes listed in primary keys is important and determines
    how the attribute values (binaries) are joined to form the primary key for
    a search or lookup.

  """
  def template(object, opts \\ []) do
    # @db_template -> "https://rest.db.ripe.net/metadata/templates"

    timeout = [opts: [recv_timeout: Keyword.get(opts, :timeout, 2_000)]]

    "#{@db_template}/#{object}.json"
    |> API.fetch(timeout)
    |> Map.put(:source, "Ripe.API.DB.template")
    |> Map.put(:type, "#{object}")
    |> decode()
  end

  # Helpers
end
