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

  ## URI path

  - `https://rest/db/ripte.net/search?param={value}&query-string={search-term}, for xml format
  - `https://rest.db.ripe.net/search.json?param={value}&query-string={search-term}`, for json format

  The `param={value}` is optional and multiple query parameters are supported (see table below).

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

  ## examples

  - https://rest.db.ripe.net/search.json?flags=B&query-string=MinVenW-MNT
  - https://rest.db.ripe.net/search.json?query-string=2a04:9a02:1800::/37
  - https://rest.db.ripe.net/search.json?flags=M&type-filter=route&query-string=131.237.0.0/16
  - https://rest.db.ripe.net/search.json?flags=B&query-string=minvenw-mnt
  - https://rest.db.ripe.net/search.json?flags=no-filtering&query-string=MN05-RIPE
  - https://rest.db.ripe.net/search.json?inverse-attribute=mb,ml&query-string=minvenw-mnt
  - https://rest.db.ripe.net/search.json?inverse-attribute=mb,ml&type-filter=route,route6&query-string=minvenw-mnt
  - https://rest.db.ripe.net/search.json?inverse-attribute=origin&type-filter=route,route6&query-string=AS42894
  - https://rest.db.ripe.net/search.json?inverse-attribute=origin&query-string=AS42894

  """

  use Tesla

  @base_url "https://rest.db.ripe.net/search.json?"

  plug(Tesla.Middleware.BaseUrl, @base_url)
  plug(Tesla.Middleware.Headers, [{"accept", "application/json"}])
  plug(Tesla.Middleware.JSON)

  alias Ripe.API.DB

  # Helpers
  # none yet

  def tmp_fetch(url) do
    # TODO: remove when no longer needed.
    url
    |> get()
    |> DB.decode()
  end

  # API

  @spec url(binary, [{binary, binary}]) :: binary
  def url(query_string, params \\ []) do
    params
    |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
    |> Enum.join("&")
    |> then(fn params -> "#{@base_url}#{params}&query-string=#{query_string}" end)
  end

  @spec fetch(binary, [{binary, binary}]) :: {:ok | :error, Tesla.Env.result()}
  def fetch(query_string, params \\ []) do
    query_string
    |> url(params)
    |> get()
  end

  # generic check on successful response
  # - return either data block OR error-tuple
  def decode({:ok, %Tesla.Env{status: 200} = body}) do
    # todo:
    # - handle decoding errors
    case Jason.decode(body.body) do
      {:ok, data} -> data
      {:error, error} -> {:error, error}
    end
  end

  def decode({:ok, %Tesla.Env{status: status} = body}) do
    # nb: body.body will be encoded as xml, ugh!
    {:error, {status, body}}
  end

  def decode({:error, msg}) do
    {:error, msg}
  end

  # endpoints
  def asn_routes(asn) do
    "#{asn}"
    |> url([{"inverse-attribute", "origin"}])
    |> tmp_fetch()
    |> put_in([:api, :query], :asn_routes)
  end

  def mntner(asn) do
    "#{asn}"
    |> url()
    |> tmp_fetch()
    |> put_in([:api, :query], :asn_mntner)
  end
end
