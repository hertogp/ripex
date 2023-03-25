defmodule Ripe.API.DB.Lookup do
  @moduledoc """

  This API is used to lookup a specific object and only returns that one object
  based on an *exact* match (if found).


  ## URI path

  `https://rest.db.ripe.net/{source}/{object-type}/{key}?flag`

  By default returns the object in xml format.  If json is preferred add `.json` to
  the end of the URI.

  where path parameters are:

  ------------ ----------------------------------------
  source        RIPE, TEST or GRS source name
  object-type   object type to lookup
  key           primary key of object to return
  ------------ ----------------------------------------

  and where query parameter(s) (`?flag`) may include:

  ------------ ----------------------------------------
  unfiltered    e-mail attributes are not filtered
  unformatted   return the original formatting
  ------------ ----------------------------------------

  ## examples

  - https://rest.db.ripe.net/ripe/inetnum/91.123.16.0 - 91.123.31.255.json
  - https://rest.db.ripe.net/ripe/inetnum/131.237.0.0/16.json
  - https://rest.db.ripe.net/ripe/role/MNO5-RIPE.json
  - https://rest.db.ripe.net/ripe/mntner/MinVenW-MNT
      returns `mntner` and `role` objects in xml format.
  - https://rest.db.ripe.net/ripe/person/GJ503-RIPE
      returns person object in xml format
  - https://rest.db.ripe.net/ripe/person/PDH108-RIPE.json
      returns person object in json format
  - https://rest.db.ripe.net/ripe/person/PDH108-RIPE.json?unfiltered
      returns person object in json format and includes the e-mail address
  - https://rest.db.ripe.net/ripe/route/131.237.0.0/17AS42894.json
      returns a route object in json format (primary key is a join of all primary keys)

  ## notes

  - when looking up ip networks, the (network part of the) key can be:
      - prefix in CIDR notation
      - block in RIPE address block notation: start-address - end-address
  - use `db.ripe.net/metadata/templates/{object-type}` to lookup an object's keys
  - in case of *multiple* primary keys, that object's primary key in a search is a *join of all keys*
      e.g. primary search key for a route object will be `<route><origin>`, ie. `<prefix><ASnr>`
  - and the order of the keys when joining matters

  """

  use Tesla

  alias Ripe.API
  alias Ripe.API.DB

  @base_url "https://rest.db.ripe.net/ripe"
  @db_lookup_url "https://rest.db.ripe.net/ripe"

  plug(Tesla.Middleware.BaseUrl, @base_url)
  plug(Tesla.Middleware.Headers, [{"accept", "application/json"}])
  plug(Tesla.Middleware.JSON)

  # TODO
  # - use Ripe.API.Cache

  # Helpers

  defp decode(%{http: 200} = result) do
    # Lookup returns only one object
    data_path = [:body, "objects", "object", 0]

    attrs =
      result
      |> IO.inspect(label: :pre)
      |> API.get_at(data_path ++ ["attributes", "attribute"])
      |> IO.inspect(label: :post)
      |> DB.collect_values_bykey("name", "value")

    primary_key =
      result
      |> API.get_at(data_path ++ ["primary-key", "attribute"])
      |> Enum.reduce("", fn m, acc -> acc <> m["value"] end)

    result
    |> Map.put(:version, API.get_at(result, [:body, "version", "version"]))
    |> Map.merge(attrs)
    |> Map.put(:primary_key, primary_key)
    |> Map.delete(:body)
  end

  # API

  defp fetch(url) do
    url
    |> API.fetch()
    |> Map.put(:source, __MODULE__)
    |> decode()
  end

  # @doc """
  # Returns the Lookup url associated with given `object`, primary-`key` and `flags`.
  #
  # """
  @spec url(binary, binary, [binary]) :: binary
  defp url(object, key, flags) do
    url =
      Enum.join([@base_url, object, key], "/")
      |> Kernel.<>(".json")
      |> URI.encode()

    flags = Enum.join(flags, "&")

    case flags do
      "" -> "#{url}"
      flags -> "#{url}?#{flags}"
    end
  end

  # API - objects

  # TODO move this to Ripe.API.DB
  def url_lookup(object, keys, flags) do
    url =
      keys
      |> Enum.join()
      |> then(fn key -> "#{@db_lookup_url}/#{object}/#{key}.json" end)

    case Enum.join(flags, "&") do
      "" -> url
      str -> url <> "?" <> str
    end
  end

  @doc """
  See
  -[Ripe Lookup](https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html#rest-api-lookup)


  """
  def lookup(object, keys, flags) do
    object
    |> url_lookup(keys, flags)
    |> API.fetch()
    |> Map.put(:source, :DB_lookup)
    |> decode()
    |> Map.put(:type, object)
  end

  @doc """
  Retrieve an [aut-num](https://apps.db.ripe.net/docs/04.RPSL-Object-Types/02-Descriptions-of-Primary-Objects.html#description-of-the-aut-num-object)
  object for given `asnr`.

  """
  def aut_num(asnr, flags \\ []) do
    "aut-num"
    |> url("#{asnr}", flags)
    |> fetch()
    |> Map.put(:type, "aut-num")
  end

  @doc """
  Retrieve a [domain](https://apps.db.ripe.net/docs/04.RPSL-Object-Types/02-Descriptions-of-Primary-Objects.html#description-of-the-domain-object)
  object for given `rev_zone` (like e.g. `1.1.1.1.in-addr.arpa`)

  """
  def domain(rev_zone, flags \\ []) do
    "domain"
    |> url("#{rev_zone}", flags)
    |> fetch()
    |> Map.put(:type, "domain")
  end

  @doc """
  Retrieve a [route](https://apps.db.ripe.net/docs/04.RPSL-Object-Types/02-Descriptions-of-Primary-Objects.html#description-of-the-route-object)
  object for given `prefix` and `ASnr`.
  """
  # @spec route(binary, binary, [binary]) :: map
  def route(prefix, asnr, flags \\ []) do
    "route"
    |> url("#{prefix}#{asnr}", flags)
    |> fetch()
    |> Map.put(:type, "route")
  end
end
