defmodule Ripe.API.DB.Template do
  @moduledoc """
  Functions to retrieve RIPE DB templates.

  Each template fetched will be decoded into a map and cached.

  See:
  - https://apps.db.ripe.net/docs/03.RIPE-Database-Structure/01-Database-Object.html
  - https://apps.db.ripe.net/docs/04.RPSL-Object-Types/

  Notes:
  - attribute names consist of alphanumeric characters plus hyphens
  - attributes names are case-insensitive, RIPE DB converts them to lowercase

  Each template is decoded into a single map with 2 special atom keys for `:type` and
  `:url`, while the other keys are the attribute names as lowercase strings.

  ```elixir
  %{
    :spec => %{
      type: "<object>",
      url: ""http://rest.db.ripe.net/metadata/templates/<object>.json"
    },
    "attr-name" => %{
      inverse: false,      # true if attr-name is in the reverse index
      lookup: true,        # false if attr-name is not a lookup key
      primary: true,       # false if it's not part of the primary key
      require: :mandatory, # other values are :required, :generated and :optional
      single: true         # false is it can occur multiple times
    },
    ...
  }
  ```

  """

  @base_url "https://rest.db.ripe.net/metadata/templates"

  use Tesla

  plug(Tesla.Middleware.BaseUrl, @base_url)
  plug(Tesla.Middleware.JSON)

  @spec url(binary) :: binary
  def url(object) do
    "#{@base_url}/#{object}.json"
  end

  @doc """
  Fetch API data for given `url` from cache (first) or the network.

  """
  @spec fetch(binary) :: map
  def fetch(url) do
    case Ripe.API.Cache.get(url) do
      nil -> do_fetch(url)
      data -> data
    end
  end

  def do_fetch(url) do
    url
    |> get()
    |> decode()
    |> Ripe.API.Cache.put(url)
  end

  def decode({:ok, %Tesla.Env{status: 200} = body}) do
    case Jason.decode(body.body) do
      {:ok, data} -> normalize(data)
      other -> {:error, {:json, other}}
    end
  end

  def decode({:ok, %Tesla.Env{status: status} = body}) do
    {:error, {status, body}}
  end

  def decode({:error, msg}) do
    {:error, msg}
  end

  defp normalize(data) when is_map(data) do
    # TODO:
    # - add `:primary_key` -> [attr-names] (order matters)
    IO.inspect(data)

    data
    |> get_in(["templates", "template"])
    |> List.first()
    |> get_in(["attributes", "attribute"])
    |> Ripe.API.map_bykey("name")
    |> attributes()
    |> Map.put(:type, get_in(data, ["templates", "template"]) |> hd() |> Map.get("type"))
    |> Map.put(:url, get_in(data, ["link", "href"]) <> ".json")
    |> primary_key()
  end

  defp normalize(data),
    do: {:error, {:normalize, data}}

  defp primary_key(data) do
    # returns a list of primary keys in correct order
    IO.inspect(data)

    primary =
      for {k, v} <- data, is_map(v) and Map.get(v, :primary, false), into: [] do
        {v.idx, k}
      end
      |> Enum.sort()
      |> Enum.map(fn elm -> elem(elm, 1) end)

    Map.put(data, :primary, primary)
  end

  def attributes(data) do
    keys = %{primary: false, inverse: false, lookup: false}

    for {key, map} <- data, is_map(map), into: %{} do
      new =
        for {k, v} <- map, into: %{} do
          to_tuple_pair(k, v)
        end

      seen = Map.get(new, :keys, keys)

      attrs =
        new
        |> Map.merge(seen)
        |> Map.delete(:keys)

      {key, attrs}
    end
  end

  defp to_tuple_pair("requirement", val) do
    case String.downcase(val) do
      "mandatory" -> {:require, :mandatory}
      "generated" -> {:require, :generated}
      "optional" -> {:require, :optional}
      "required" -> {:require, :required}
      _ -> {:mandatory, false}
    end
  end

  defp to_tuple_pair("cardinality", val) do
    case String.downcase(val) do
      "single" -> {:single, true}
      _ -> {:single, false}
    end
  end

  defp to_tuple_pair("keys", list) do
    # return a full list of keys with true/false
    keys = %{primary: false, inverse: false, lookup: false}

    attrs =
      Enum.reduce(list, keys, fn key, acc ->
        case String.downcase(key) do
          "primary_key" -> Map.put(acc, :primary, true)
          "lookup_key" -> Map.put(acc, :lookup, true)
          "inverse_key" -> Map.put(acc, :inverse, true)
        end
      end)

    {:keys, attrs}
  end

  defp to_tuple_pair(key, val) do
    # retain unknown tuple pair
    {key, val}
  end
end
