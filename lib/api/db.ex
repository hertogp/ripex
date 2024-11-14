defmodule Ripe.API.DB do
  @moduledoc """
  Functions to retrieve
  [objects](https://apps.db.ripe.net/docs/04.RPSL-Object-Types/#rpsl-object-types)
  from the RIPE NCC
  [database](https://apps.db.ripe.net/docs/) using some of its RESTful
  [API](https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html)'s.

  Note that the
  [Fair Use Policy](https://www.ripe.net/manage-ips-and-asns/db/support/documentation/ripe-database-acceptable-use-policy),
  includes some limits:
  - unlimited number of queries for a given IP address, as long as you do not disrupt the service
  - max 1000 personal data-sets per 24 hours (see `search/2` and the `flags: "r"`)
  - max 3 simultaneous connections per IP address

  It's easy to accidently violate the personal data-sets limit  when searching the database. So beware.

  All functions support an optional `timeout: N` parameter, since some queries may take longer than 2 seconds
  (the default) to complete.  `N` is in milliseconds.

  The documentation of the RESTful
  [API](https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html)'s
  is sometimes a bit outdated.  The geolocation API doesn't seem to work and an alternative seems to live at
  [ipmap.ripe.net](https://ipmap.ripe.net/docs/02.api-reference/).
  """

  alias Ripe.API

  # [[ TODO: ]]
  # - add subAPI https://ipmap.ripe.net/ (since rest.db.ripe.net/geolocation doesn't work anymore)
  #   `-> see https://ipmap.ripe.net/docs/02.api-reference/
  # - add flags: "r" by default to help avoid retrieving too much personal data (and get blocked)
  # - use the TEST database, but how?  Nothting seems to work and documentation is out of date it seems.
  # - fake todo
  #
  # GRS=Global Resource Service, one of: RIPE, RADb, APNIC, ARIN, AfriNIC, LACNIC

  # [[ HELPERS ]]

  @spec new(binary, Keyword.t()) :: Req.Request.t()
  defp new(url, opts) do
    # request for Ripe DB endpoint given by url (and opts)
    Req.new(
      url: url,
      base_url: "https://rest.db.ripe.net",
      json: true,
      headers: [accept: "application/json", user_agent: "ripex"]
    )
    |> Req.merge(opts)
  end

  @spec collect_keys_byvalue(map, fun()) :: [binary]
  defp collect_keys_byvalue(map, fun) when is_map(map) do
    # collect keys by value using given `fun` and sort keys on idx field if any
    for {k, m} <- map, fun.(m), into: [] do
      {m[:idx], k}
    end
    |> Enum.sort()
    |> Enum.map(fn {_, k} -> k end)
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
  defp decode(%{source: "Ripe.API.DB.abuse_c", http: 200} = result) do
    # abuse_c doesn't really return an RPSL object

    obj = result[:body]["abuse-contacts"]
    primary_key = result[:body]["parameters"]["primary-key"]["value"]

    result
    |> Map.merge(obj)
    |> Map.put(:primary_key, primary_key)
    |> Map.delete(:body)
  end

  defp decode(%{source: "Ripe.API.DB.abuse_c"} = result) do
    # not a http: 200 -> error, 301 is redirect with empty body (redirect
    # contains the error messages)
    msg = result[:body]["message"]

    result
    |> Map.put(:error, msg)
    |> Map.delete(:body)
  end

  defp decode(%{source: "Ripe.API.DB.lookup", http: 200} = result) do
    # lookup returns only one object

    obj =
      result[:body]["objects"]["object"]
      |> hd()
      |> decode_obj()

    version = result[:body]["version"]["version"]

    result
    |> Map.put(:version, version)
    |> Map.merge(obj)
    |> Map.delete(:body)
  end

  defp decode(%{source: "Ripe.API.DB.lookup"} = result) do
    # not a http: 200 -> error, 301 is redirect with empty body (redirect
    # contains the error messages)
    result
    |> Map.put(:error, decode_err(result))
    |> Map.delete(:body)
  end

  defp decode(%{source: "Ripe.API.DB.search", http: 200} = result) do
    # search returns one or more objects

    objects =
      result[:body]["objects"]["object"]
      |> Enum.map(&decode_obj/1)

    version = result[:body]["version"]["version"]

    result
    |> Map.put(:objects, objects)
    |> Map.put(:version, version)
    |> Map.delete(:body)
  end

  defp decode(%{source: "Ripe.API.DB.search"} = result) do
    # not a http: 200 -> error

    result
    |> Map.put(:error, decode_err(result))
    |> Map.delete(:body)
  end

  defp decode(%{source: "Ripe.API.DB.template", http: 200} = result) do
    # template returns only one object in its own formatt

    data = result[:body]["templates"]["template"] |> hd()
    attrs = API.map_bykey(data["attributes"]["attribute"], "name")

    p_keys = collect_keys_byvalue(attrs, fn m -> "PRIMARY_KEY" in Map.get(m, "keys", []) end)
    l_keys = collect_keys_byvalue(attrs, fn m -> "LOOKUP_KEY" in Map.get(m, "keys", []) end)
    i_keys = collect_keys_byvalue(attrs, fn m -> "INVERSE_KEY" in Map.get(m, "keys", []) end)

    result
    |> Map.put(:rir, data["source"]["id"])
    |> Map.put(:type, data["type"])
    |> Map.put(:primary_keys, p_keys)
    |> Map.put(:inverse_keys, i_keys)
    |> Map.put(:lookup_keys, l_keys)
    |> Map.delete(:body)
    |> Map.merge(attrs)
  end

  defp decode(%{source: "Ripe.API.DB.template"} = result) do
    # not a http: 200 -> error

    result
    |> Map.put(:error, result[:body]["message"])
    |> Map.delete(:body)
  end

  @spec decode_err(map) :: binary
  defp decode_err(obj) do
    (obj[:body]["errormessages"]["errormessage"] ||
       [%{"text" => "unknown error"}])
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
    # decode a single RPSL object
    attrs =
      obj["attributes"]["attribute"]
      |> collect_values_bykey("name", "value")

    primary_key =
      obj["primary-key"]["attribute"]
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
  Retrieves [abuse-contact](https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html#rest-api-abuse-contact)
  information, if possible, for given `key`.

  where:
  - `key` is either an ASnr, IP Prefix or an IP address.

  Upon success, a map is returned with keys:
  - `:headers`, the response's headers
  - `:http`, 200
  - `:method`, :get
  - `:opts`, options given to the http client
  - `:primary_key`, primary key for object found
  - `:source`, "Ripe.API.DB.abuse_c"
  - `:url`, the url used to retrieve the information
  - `"email"`, some email address
  - `"key"`, nic-handle of a role or a person
  - `"org-id"`,  nic-handle of an organisation
  - `"suspect"`, false (or true :)

  Upon failure, a map is returned with keys:
  - `error:`, some reason
  - `http:`, 400 (usually)
  - `method:`, :get
  - `opts:`, options given to the http client
  - `source:` "Ripe.API.DB.abuse_c"
  - `url:`, the url that was used

  Note that even if the call returns successful, there might not be any contact
  information available (i.e. it doesn't return a 404).

  ## Examples

  Abuse contact for an AS:

      iex> abuse_c("AS3333")
      %{
        :http => 200,
        :method => :get,
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
        source: "Ripe.API.DB.abuse_c",
        url: "https://rest.db.ripe.net/abuse-contact/1.1.1.x.json"
      }

  Weirdly enough, using an IPv6 address apparently does yield a 404 when there
  is no contact information available.

      iex(339)> Ripe.API.DB.abuse_c("::1.1.1.1")
      %{
        error: "No abuse contact found for ::1.1.1.1",
        http: 404,
        method: :get,
        source: "Ripe.API.DB.abuse_c",
        url: "https://rest.db.ripe.net/abuse-contact/::1.1.1.1.json"
      }
  """
  @spec abuse_c(binary, Keyword.t()) :: map
  def abuse_c(key, opts \\ []) do
    "/abuse-contact/#{key}.json"
    |> new(opts)
    |> API.call()
    |> Map.drop([:headers, :opts])
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
  keys for the attributes returned by RIPE.

  ## Examples

  A RIPE route object:

      iex> lookup("route", "193.0.0.0/21AS3333") |> Map.delete(:version)
      %{
        :http => 200,
        :method => :get,
        :primary_key => "193.0.0.0/21AS3333",
        :source => "Ripe.API.DB.lookup",
        :type => "route",
        :url => "https://rest.db.ripe.net/ripe/route/193.0.0.0/21AS3333.json",
        "created" => ["1970-01-01T00:00:00Z"],
        "descr" => ["RIPE-NCC"],
        "last-modified" => ["2008-09-10T14:27:53Z"],
        "mnt-by" => ["RIPE-NCC-MNT"],
        "origin" => ["AS3333"],
        "route" => ["193.0.0.0/21"],
        "source" => ["RIPE"],
        "type" => "route"
      }

  No results found due to missing ASnr in the primary key used:

      iex> lookup("route", "193.0.0.0/21")
      %{
        error: "ERROR:101: no entries found\\n\\nNo entries found in source RIPE.\\n",
        http: 404,
        method: :get,
        source: "Ripe.API.DB.lookup",
        type: "route",
        url: "https://rest.db.ripe.net/ripe/route/193.0.0.0/21.json"
      }

  """
  @spec lookup(binary, binary, Keyword.t()) :: map
  def lookup(type, key, opts \\ []) do
    "/ripe/#{type}/#{key}.json"
    |> new(opts)
    |> API.call()
    |> Map.put(:source, "Ripe.API.DB.lookup")
    |> Map.put(:type, type)
    |> Map.drop([:headers, :opts])
    |> decode()
  end

  @doc """
  Retrieves one or more objects via a Ripe
  [search](https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html#rest-api-search).

  The `query` parameter specifies the string value to search for.  By default this will find objects
  whose primary key matches or have a lookup key that (partially) matches.

  See also:
  - [primary vs lookup keys](https://apps.db.ripe.net/docs/13.Types-of-Queries/01-Queries-Using-Primary-and-Lookup-Keys.html#queries-using-primary-and-lookup-keys)
  - [what is returned](https://apps.db.ripe.net/docs/16.Tables-of-Query-Types-Supported-by-the-RIPE-Database/#table-1-queries-using-primary-and-lookup-keys)

  See `Req.new/1` to see the list of options that can be passed to `Ripe.API.db_req/2`.
  The most used options include:
  - `receive_timeout: N`, for timeout in milliseconds for a reply
  - `params:`, to pass in query parameters not encoded in the `query` itself (see below)


  Use `:params` to list additional [query
  parameters](https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html#uri-query-parameters)
  in the form of `[{"name", ["value", ...]}, ..]` as needed.  They include:

  - `source:`, the name or list of names of the sources to be searched
  - `"inverse-attribute":`,  the name or list of names of inverse indexed attributes to search
  - `"include-tag":`, name or csv-list of names of tags that RPSL objects must have
  - `"exclude-tag":`, name or csv-list of names of tags that RPSL objects cannot have
  - `"type-filter":`, type or csv-list of types the returned objects must have
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
  amount of contact information you can retrieve in a day.  You can either repeat the `flags:` parameter
  or simply list all flags in a string, e.g. `params: [flags: "rG"]`

  ## Examples

  - `search("as3333", params: ["inverse-attribute": "origin"])`
    - find all route(6) objects whose origin matches as3333

  - `search("RIPE-NCC-MNT", params: ["inverse-attribute": "mnt-by", flags: "r", "type-filter": "domain"])`
    - find all domains maintained by RIPE-NCC-MNT, without any additional contact information

  - `search("RIPE-NCC-MNT", params: ["inverse-attribute": "mnt-by", "type-filter": "inetnum,inet6num", flags: "rG"])`
    - find all inet(6)num's maintained by RIPE-NCC-MNT, without additional contact information or grouping

  Search for a route object given a certain prefix.

      iex> Ripe.API.DB.search("193.0.0.0/21", params: [flags: "r", "type-filter": "route"])
      ...> |> Map.drop([:version])
      %{
        http: 200,
        method: :get,
        objects: [
          %{
            :primary_key => "193.0.0.0/21AS3333",
            "created" => ["1970-01-01T00:00:00Z"],
            "descr" => ["RIPE-NCC"],
            "last-modified" => ["2008-09-10T14:27:53Z"],
            "mnt-by" => ["RIPE-NCC-MNT"],
            "origin" => ["AS3333"],
            "route" => ["193.0.0.0/21"],
            "source" => ["RIPE"],
            "type" => "route"
          }
        ],
        query: "193.0.0.0/21",
        source: "Ripe.API.DB.search",
        url: "https://rest.db.ripe.net/search.json?query-string=193.0.0.0/21&flags=r&type-filter=route",
      }

    Find both the inetnum and route objects.

      iex> Ripe.API.DB.search("193.0.0.0/21", params: [flags: "r", "type-filter": "route,inetnum"])
      ...> |> Map.drop([:version])
      %{
        http: 200,
        method: :get,
        objects: [
          %{
            :primary_key => "193.0.0.0 - 193.0.7.255",
            "admin-c" => ["BRD-RIPE"],
            "country" => ["NL"],
            "created" => ["2003-03-17T12:15:57Z"],
            "descr" => ["RIPE Network Coordination Centre", "Amsterdam, Netherlands"],
            "inetnum" => ["193.0.0.0 - 193.0.7.255"],
            "last-modified" => ["2017-12-04T14:42:31Z"],
            "mnt-by" => ["RIPE-NCC-MNT"],
            "netname" => ["RIPE-NCC"],
            "org" => ["ORG-RIEN1-RIPE"],
            "remarks" => ["Used for RIPE NCC infrastructure."],
            "source" => ["RIPE"],
            "status" => ["ASSIGNED PA"],
            "tech-c" => ["OPS4-RIPE"],
            "type" => "inetnum"
          },
          %{
            :primary_key => "193.0.0.0/21AS3333",
            "created" => ["1970-01-01T00:00:00Z"],
            "descr" => ["RIPE-NCC"],
            "last-modified" => ["2008-09-10T14:27:53Z"],
            "mnt-by" => ["RIPE-NCC-MNT"],
            "origin" => ["AS3333"],
            "route" => ["193.0.0.0/21"],
            "source" => ["RIPE"],
            "type" => "route"
          }
        ],
        query: "193.0.0.0/21",
        source: "Ripe.API.DB.search",
        url: "https://rest.db.ripe.net/search.json?query-string=193.0.0.0/21&flags=r&type-filter=route%2Cinetnum",
      }

  """
  @spec search(binary, Keyword.t()) :: map
  def search(query, opts \\ []) do
    "search.json?query-string=#{query}"
    |> new(opts)
    |> API.call()
    |> Map.put(:source, "Ripe.API.DB.search")
    |> Map.put(:query, query)
    |> Map.drop([:headers, :opts])
    |> decode()
  end

  @doc """
  Retrieves a
  [template](https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html#metadata-object-template)
  for given `object`-type.

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

  Since the order in which attributes are listed in a template is important, the
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
    how the attribute values (binaries) are joined (without a separator) to
    form the primary key for a search or lookup.

  ## Example

      iex> template("domain")
      %{
        :http => 200,
        :inverse_keys => ["org", "admin-c", "tech-c", "zone-c", "nserver",
          "ds-rdata", "notify", "mnt-by"],
        :lookup_keys => ["domain"],
        :method => :get,
        :primary_keys => ["domain"],
        :rir => "ripe",
        :source => "Ripe.API.DB.template",
        :type => "domain",
        :url => "https://rest.db.ripe.net/metadata/templates/domain.json",
        "admin-c" => %{
          :idx => 3,
          "cardinality" => "MULTIPLE",
          "keys" => ["INVERSE_KEY"],
          "requirement" => "MANDATORY"
        },
        "created" => %{
          :idx => 11,
          "cardinality" => "SINGLE",
          "requirement" => "GENERATED"
        },
        "descr" => %{
          :idx => 1,
          "cardinality" => "MULTIPLE",
          "requirement" => "OPTIONAL"
        },
        "domain" => %{
          :idx => 0,
          "cardinality" => "SINGLE",
          "keys" => ["PRIMARY_KEY", "LOOKUP_KEY"],
          "requirement" => "MANDATORY"
        },
        "ds-rdata" => %{
          :idx => 7,
          "cardinality" => "MULTIPLE",
          "keys" => ["INVERSE_KEY"],
          "requirement" => "OPTIONAL"
        },
        "last-modified" => %{
          :idx => 12,
          "cardinality" => "SINGLE",
          "requirement" => "GENERATED"
        },
        "mnt-by" => %{
          :idx => 10,
          "cardinality" => "MULTIPLE",
          "keys" => ["INVERSE_KEY"],
          "requirement" => "MANDATORY"
        },
        "notify" => %{
          :idx => 9,
          "cardinality" => "MULTIPLE",
          "keys" => ["INVERSE_KEY"],
          "requirement" => "OPTIONAL"
        },
        "nserver" => %{
          :idx => 6,
          "cardinality" => "MULTIPLE",
          "keys" => ["INVERSE_KEY"],
          "requirement" => "MANDATORY"
        },
        "org" => %{
          :idx => 2,
          "cardinality" => "MULTIPLE",
          "keys" => ["INVERSE_KEY"],
          "requirement" => "OPTIONAL"
        },
        "remarks" => %{
          :idx => 8,
          "cardinality" => "MULTIPLE",
          "requirement" => "OPTIONAL"
        },
        "source" => %{
          :idx => 13,
          "cardinality" => "SINGLE",
          "requirement" => "MANDATORY"
        },
        "tech-c" => %{
          :idx => 4,
          "cardinality" => "MULTIPLE",
          "keys" => ["INVERSE_KEY"],
          "requirement" => "MANDATORY"
        },
        "zone-c" => %{
          :idx => 5,
          "cardinality" => "MULTIPLE",
          "keys" => ["INVERSE_KEY"],
          "requirement" => "MANDATORY"
        }
      }



  """
  @spec template(binary, Keyword.t()) :: map
  def template(type, opts \\ []) do
    "/metadata/templates/#{type}.json"
    |> new(opts)
    |> API.call()
    |> Map.put(:source, "Ripe.API.DB.template")
    |> Map.put(:type, "#{type}")
    |> Map.drop([:headers, :opts])
    |> decode()
  end
end
