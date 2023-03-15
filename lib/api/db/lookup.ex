defmodule Ripe.API.DB.Lookup do
  @moduledoc """

  This API is used to lookup a specific object and only returns that one object
  based on an *exact* match (if found).

  See
  - [REST API Lookup](https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html)
  - [database structure](https://apps.db.ripe.net/docs/03.RIPE-Database-Structure/01-Database-Object.html)
  - [object types](https://apps.db.ripe.net/docs/04.RPSL-Object-Types/#rpsl-object-types)
      - [primary objects](https://apps.db.ripe.net/docs/04.RPSL-Object-Types/02-Descriptions-of-Primary-Objects.html#descriptions-of-primary-objects)
      - [secondary objects](https://apps.db.ripe.net/docs/04.RPSL-Object-Types/03-Descriptions-of-Secondary-Objects.html#descriptions-of-secondary-objects)

  ## URI path

  `https://rest.db.ripe.net/{source}/{object-type}/{key}?flag`

  By default returns the object in xml format.  If json is preferred add `.json` to
  the end of the URI.

  where path parameters are:

  ------------  ----------------------------------------
  source        RIPE, TEST or GRS source name
  object-type   object type to lookup
  key           primary key of object to return
  ------------  ----------------------------------------

  and where query parameter(s) (`?flag`) may include:

  ------------  ----------------------------------------
  unfiltered    e-mail attributes are not filtered
  unformatted   return the original formatting
  ------------  ----------------------------------------

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
  alias Ripe.API.DB

  @base_url "https://rest.db.ripe.net/ripe"

  plug(Tesla.Middleware.BaseUrl, @base_url)
  plug(Tesla.Middleware.Headers, [{"accept", "application/json"}])
  plug(Tesla.Middleware.JSON)

  # Helpers

  # defp decodep(data) do
  #   # Notes:
  #   # - we rely on the fact that only one object will be returned.
  #
  #   obj = Ripe.API.get_at(data, ["objects", "object", 0])
  #
  #   data
  #   |> Ripe.API.get_at(["objects", "object", 0, "attributes", "attribute"])
  #   |> Ripe.API.map_bykey("name")
  #   |> Ripe.API.promote("value")
  #   |> Map.put(:version, Ripe.API.get_at(data, ["version", "version"]))
  #   |> Map.put(:url, Ripe.API.get_at(obj, ["link", "href"]) <> ".json")
  #   |> Map.put(:type, Map.get(obj, "type"))
  #   |> Map.put(:primary_key, primary_key(obj))
  #   |> Map.delete("version")
  #   |> Map.delete("terms-and-conditions")
  # end
  #
  # defp primary_key(obj) do
  #   for map <- Ripe.API.get_at(obj, ["primary-key", "attribute"]), into: [] do
  #     map["value"]
  #   end
  #   |> Enum.join()
  # end

  # defp do_fetch(url) do
  #   # called when cache comes up empty for given `url`
  #   url
  #   |> get()
  #   |> decode()
  #   |> Ripe.API.Cache.put(url)
  # end

  # API

  def tmp_fetch(url) do
    # TODO: remove when no longer needed.
    url
    |> get()
    |> DB.decode()
  end

  @doc """
  Returns the Lookup url associated with given `object`, primary-`key` and `flags`.

  """
  @spec url(binary, binary, [binary]) :: binary
  def url(object, key, flags \\ []) do
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

  # @spec fetch(binary) :: any
  # def fetch(url) do
  #   case Ripe.API.Cache.get(url) do
  #     nil -> do_fetch(url)
  #     data -> data
  #   end
  # end

  # generic check on successful response
  # - return either data block OR error-tuple
  # def decode({:ok, %Tesla.Env{status: 200} = body}) do
  #   # todo:
  #   # - handle decoding errors
  #   case Jason.decode(body.body) do
  #     {:ok, data} -> decodep(data)
  #     {:error, error} -> {:error, error}
  #   end
  # end
  #
  # def decode({:ok, %Tesla.Env{status: status} = body}) do
  #   # nb: body.body will be encoded as xml, ugh!
  #   {:error, {status, body}}
  # end

  # def decode({:error, msg}) do
  #   {:error, msg}
  # end

  # API - objects
  @doc """
  Retrieve a route object for given `prefix` and `ASnr`.
  """
  # @spec route(binary, binary, [binary]) :: map
  def route(prefix, asnr, flags \\ []) do
    "route"
    |> url("#{prefix}#{asnr}", flags)
    |> tmp_fetch()
  end
end
