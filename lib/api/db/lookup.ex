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

  """

  use Tesla

  @base_url "https://rest.db.ripe.net/ripe"

  plug(Tesla.Middleware.BaseUrl, @base_url)
  plug(Tesla.Middleware.JSON)

  # Helpers
  # none yet

  # API

  @spec url(binary, binary, [binary]) :: binary
  def url(object, key, flags \\ []) do
    [@base_url, object, key, flags]
    |> List.flatten()
    |> Enum.join("/")
    |> Kernel.<>(".json")
  end

  @spec fetch(binary) :: {:ok | :error, Tesla.Env.result()}
  def fetch(url) do
    case Ripe.API.Cache.get(url) do
      nil -> do_fetch(url)
      data -> data
    end
  end

  defp do_fetch(url) do
    url
    |> get()
    |> Ripe.API.Cache.put(url)
  end

  # generic check on successful response
  # - return either data block OR error-tuple
  def decode({:ok, %Tesla.Env{status: 200} = body}) do
    # todo:
    # - handle decoding errors
    case Jason.decode(body.body) do
      {:ok, data} -> decodep(data)
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

  defp decodep(data) do
    version = Map.get(data, "version", %{}) |> Map.get("version", "0.0")

    object =
      data
      |> get_in(["objects", "object"])
      |> List.first()
      |> get_in(["attributes", "attribute"])
      |> Ripe.API.map_bykey("name")

    IO.inspect(object)

    data
    |> Map.put(:spec, %{:version => version})
    |> Map.delete("version")
    |> Map.delete("terms-and-conditions")
  end
end
