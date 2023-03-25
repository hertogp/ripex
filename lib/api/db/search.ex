defmodule Ripe.API.DB.Search do
  @moduledoc """

  This offers the well known whois search via a rest-like interface.

  See:
  - [query types](https://apps.db.ripe.net/docs/13.Types-of-Queries/#types-of-queries)
  - [API queries](https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html)
  - [database structure](https://apps.db.ripe.net/docs/03.RIPE-Database-Structure/01-Database-Object.html)
  - [object types](https://apps.db.ripe.net/docs/04.RPSL-Object-Types/#rpsl-object-types)
    - [primary objects](https://apps.db.ripe.net/docs/04.RPSL-Object-Types/02-Descriptions-of-Primary-Objects.html#descriptions-of-primary-objects)
    - [secondary objects](https://apps.db.ripe.net/docs/04.RPSL-Object-Types/03-Descriptions-of-Secondary-Objects.html#descriptions-of-secondary-objects)

  See:
  - [API search](https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html#rest-api-search)
  - [URL parameters](https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html#uri-query-parameters)
  - [flags](https://apps.db.ripe.net/docs/13.Types-of-Queries/#types-of-queries)
  - [query-types](https://apps.db.ripe.net/docs/16.Tables-of-Query-Types-Supported-by-the-RIPE-Database/#tables-of-query-types-supported-by-the-ripe-database)

  URL query parameters:

  --------------------  --------------------------------------------------------------
  query-string          mandatory, the actual search term
  source                opt, default=ripe
  inverse-attribute     opt, look for search term in inv attribute given
  include-tag           opt, only show RPSL objects with given tags (repeatable)
  exclude-tag           opt, only show RPSL objects without given tags (repeatable)
  type-filter           opt, only show given obj-types (repeatable)
  flags                 opt, query-flags (repeatable)
  unformatted           opt, show unformatted RPSL objects (preserve spaces,tabs etc)
  managed-attributes    opt, flag which RPSL attr are managed by RIPE
  resource-holder       opt, include resource holder Organisation (id and name)
  abuse-contact         opt, include abuse-c email of the resource (if any)
  limit                 opt, max nr of RPSL obj's to return in the response
  offset                opt, return RPSL obj's from a specified offset (paging?)
  --------------------  --------------------------------------------------------------

  The information regarding the possible query `flags=..` is a bit scattered but:
  - [flags](https://apps.db.ripe.net/docs/13.Types-of-Queries/#types-of-queries)
  - [flags & ip networks](https://apps.db.ripe.net/docs/16.Tables-of-Query-Types-Supported-by-the-RIPE-Database/#table-2-queries-for-ip-networks-table)
  - [flags & inverse keys](https://apps.db.ripe.net/docs/16.Tables-of-Query-Types-Supported-by-the-RIPE-Database/#table-3-query-flag-arguments-to-the-query-flag-and-the-corresponding-inverse-keys)
  - [flags & tools](https://apps.db.ripe.net/docs/16.Tables-of-Query-Types-Supported-by-the-RIPE-Database/#table-4-query-support-for-tools)
  - [flags & miscellaneous](https://apps.db.ripe.net/docs/16.Tables-of-Query-Types-Supported-by-the-RIPE-Database/#table-5-miscellaneous-queries)
  - [flags & information](https://apps.db.ripe.net/docs/16.Tables-of-Query-Types-Supported-by-the-RIPE-Database/#table-6-informational-queries)
  should be a good start.

  Some of the interesting `flags` include:

  --------------------  --------------------------------------------------------------
  B                     unfiltered?
  k                     persistent connectin
  G                     turn grouping off
  M (all-more)          include all more specific matches
  m (one-more)          include 1-level more specific
  L (all-less)          include less specific matches
  l (one-less)          include 1-level less specific
  x (..)                exact match (domain objects)
  i (inverse)
  --------------------  --------------------------------------------------------------

  See also:
  - [primary vs lookup keys](https://apps.db.ripe.net/docs/13.Types-of-Queries/01-Queries-Using-Primary-and-Lookup-Keys.html#queries-using-primary-and-lookup-keys)
  - [what is returned](https://apps.db.ripe.net/docs/16.Tables-of-Query-Types-Supported-by-the-RIPE-Database/#table-1-queries-using-primary-and-lookup-keys)

  """

  use Tesla

  @base_url "https://rest.db.ripe.net/search.json?"

  plug(Tesla.Middleware.BaseUrl, @base_url)
  plug(Tesla.Middleware.Headers, [{"accept", "application/json"}])
  plug(Tesla.Middleware.JSON)

  alias Ripe.API
  alias Ripe.API.DB

  # Helpers

  defp decode(%{http: 200} = result) do
    # Search returns one or more objects
    data_path = [:body, "objects", "object"]

    IO.inspect(result, label: :result)

    objects =
      result
      |> API.get_at(data_path)
      |> Enum.reduce([], fn obj, acc ->
        attrs =
          obj
          |> IO.inspect()
          |> API.get_at(["attributes", "attribute"])
          |> IO.inspect()
          |> DB.collect_values_bykey("name", "value")

        primary_key =
          obj
          |> API.get_at(["primary-key", "attribute"])
          |> Enum.reduce("", fn m, acc -> acc <> m["value"] end)

        map =
          obj
          |> Map.put(:type, Map.get(obj, "type", "unknown"))
          |> Map.merge(attrs)
          |> Map.put(:primary_key, primary_key)
          |> Map.delete("attributes")
          |> Map.delete("primary-key")
          |> Map.delete("link")

        [map | acc]
      end)

    result
    |> Map.put(:version, API.get_at(result, [:body, "version", "version"]))
    |> Map.put(:objects, objects)
    |> Map.delete(:body)
  end

  defp decode(result) do
    # note: this interpolates the '%s' in "text" string with "args"'s values
    # %{
    #   "args" => [%{"value" => "RIPE"}],
    #   "severity" => "Error",
    #   "text" => "ERROR:101: no entries found\n\nNo entries found in source %s.\n"
    # }
    IO.inspect(result)

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

  defp fetch(url) do
    url
    |> API.fetch()
    |> Map.put(:source, __MODULE__)
    |> decode()
  end

  @spec url(binary, [{binary, binary}]) :: binary
  defp url(query_string, params \\ []) do
    params
    |> IO.inspect(label: :params)
    |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
    |> Enum.join("&")
    |> then(fn params -> "#{@base_url}#{params}&query-string=#{query_string}" end)
  end

  # API

  @doc """
  Search for objects having `key` in one of given inverse `inverse_attributes`.

  See [RPSL types](https://apps.db.ripe.net/docs/04.RPSL-Object-Types/) for
  more information on object, attributes and their indexing.

  If no

  """
  def by_inverse_key(query, inverse_keys) when is_list(inverse_keys) do
    inv_attrs =
      inverse_keys
      |> Enum.map(fn type -> {"inverse-attribute", "#{type}"} end)

    type =
      case inv_attrs do
        [] -> "search"
        _ -> "by-inverse-attributes"
      end

    "#{query}"
    |> url(inv_attrs)
    |> fetch()
    |> IO.inspect()
    |> Map.put(:type, type)
    |> Map.put(:query, "#{query}")
  end

  def domain(revzone) do
    "#{revzone}"
    |> url()
    |> fetch()
    |> Map.put(:type, "domain")
  end

  def domains_by_mntner(mntner) do
    "#{mntner}"
    |> url([{"inverse-attribute", "mnt-by"}, {"type-filter", "domain"}])
    |> fetch()
    |> Map.put(:type, "domain_mnt_by")
  end

  @doc """
  Retrieve a mntner object for given `asn`.

  """
  def mntner(asn) do
    "#{asn}"
    |> url()
    |> fetch()
    |> Map.put(:type, "mntner")
  end

  @doc """
  Retrieves routes whose, mandatory, origin attribute matches given `asn`.

  """
  def routes_by_origin(asn) do
    "#{asn}"
    |> url([{"inverse-attribute", "origin"}])
    |> fetch()
    |> Map.put(:type, "routes-by-origin")
  end
end
