defmodule Ripe.API do
  @moduledoc """
  Utility functions to be used by all endpoints across all RIPE API's.

  Since all RIPE queries are fully encoded in the url, `Ripe.API.Cache`
  is used in order to prevent hammering Ripe unnecessarily.

  """

  use Tesla, only: [:get], docs: false
  plug(Tesla.Middleware.Headers, [{"accept", "application/json"}])
  plug(Tesla.Middleware.FollowRedirects, max_redirects: 3)
  plug(Tesla.Middleware.JSON)

  alias Ripe.API.Cache

  # Helpers

  @spec decode(Tesla.Env.result()) :: map
  defp decode({:ok, env}) do
    # Note: no env.headers since we're following redirects.
    %{
      url: env.url,
      http: env.status,
      body: env.body,
      method: env.method,
      opts: env.opts
    }
  end

  defp decode({:error, msg}),
    do: %{error: msg, http: -1}

  # API

  @doc """
  Returns a map containing the decoded response from Ripe based on given `url`.

  In case of a successful `t:Tesla.Env.result/0`, the map contains atom keys:
  - `:url`, the url visited
  - `:http`, the https status of the call, (-1 if an error occurred)
  - `:body`, the body of the result
  - `:method`, http method used, usually jus `:get`
  - `opts`, any options passed to Tesla (like recv_timeout)

  Note that this might still mean that the endpoint had problems returning
  any usefull data.

  In case of any errors, the map contains:
  - `:http`, which is given the value of `-1`
  - `:error`, with some message

  Note:
  - specify a timeout via: `[opts: [recv_timeout: 10_000]]`
  - It's up to the caller to further decode the body of the response.

  """
  @spec fetch(binary, Keyword.t()) :: map
  def fetch(url, opts \\ []) do
    # See https://hexdocs.pm/tesla/Tesla.Env.html#content
    # Once all API endpoints are stable, we'll cache the decode result
    # instead of the raw response.
    # TODO: add force: true to opts to ignore the cache.

    case Cache.get(url) do
      nil ->
        url
        |> get(opts)
        |> Cache.put(url)

      data ->
        data
    end
    |> decode()
  end

  @spec get_at(map | list, [atom | binary | number], any) :: any
  def get_at(data, keys, default \\ nil)

  def get_at(data, [], _default),
    do: data

  def get_at(data, [key | tail], default) when is_map(data) do
    data
    |> Map.get(key, nil)
    |> get_at(tail, default)
  end

  def get_at(data, [key | tail], default) when is_list(data) do
    data
    |> List.pop_at(key)
    |> elem(0)
    |> get_at(tail, default)
  end

  def get_at(_, _, default),
    do: default

  @doc """
  Given a map, promote values that consist of a single given `key` => value.
  """
  @spec promote(map, binary) :: map
  def promote(map, key) when is_map(map) do
    promoted =
      for {k, v} <- map, is_map(v) and Map.has_key?(v, key), into: %{} do
        {k, Map.get(v, key)}
      end

    Map.merge(map, promoted)
  end

  def move_keyup(map, key, opts \\ []) do
    name = Keyword.get(opts, :rename, key)
    func = Keyword.get(opts, :transform, fn x -> x end)

    promoted =
      for {_k, v} <- map, is_map(v) and Map.has_key?(v, key), into: %{} do
        {name, Map.get(v, key) |> func.()}
      end

    Map.merge(map, promoted)
  end

  @doc """
  Rename keys in `map` using `keymap`, recursively.

  This function will recurse on values that are either a map or list themselves.
  """
  @spec rename(map, map) :: map
  def rename(map, keymap) when is_map(map) do
    for {k, v} <- map, into: %{} do
      knew = Map.get(keymap, k, k)

      cond do
        is_map(v) -> {knew, rename(v, keymap)}
        is_list(v) -> {knew, Enum.map(v, fn elm -> rename(elm, keymap) end)}
        true -> {knew, v}
      end
    end
  end

  def rename(data, _keymap),
    do: data

  @doc """
  Reduce a `list` of similar maps to a map by `key`.

  The maps in the list should share a common key with
  values unique compared to the other maps in the list.

  Each map in the list is added to an accumulator map
  using the common key's value (`map[key]`) as the key
  in the accumulator map, while also dropping `map[key]`
  from the individual map and adding a `:idx` key,value
  pair that records its original position in the list.


  """
  @spec map_bykey(list, binary) :: map
  def map_bykey(list, key) when is_list(list) do
    for {map, idx} <- Enum.with_index(list), Map.has_key?(map, key), into: %{} do
      new_key = map[key]

      map =
        map
        |> Map.put(:idx, idx)
        |> Map.delete(key)

      {new_key, map}
      # {map[key], Map.delete(map, key)}
    end
  end

  # recursively remove keys
  @doc """
  Dop given `keys` from `map`, recursively.

  This function will recurse on values that are either a map or list themselves.

  """
  @spec remove(map, [binary]) :: map
  def remove(map, keys) when is_map(map) do
    for {k, v} <- Map.drop(map, keys), into: %{} do
      cond do
        is_map(v) -> {k, remove(v, keys)}
        is_list(v) -> {k, Enum.map(v, fn elm -> remove(elm, keys) end)}
        true -> {k, v}
      end
    end
  end

  # only remove keys from a map
  def remove(data, _keys),
    do: data
end
