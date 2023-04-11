defmodule Ripe.API do
  @moduledoc """
  Utility functions used by all endpoints across all RIPE API's.

  Besides the `fetch/2` function, some additional generic decoding functions are
  included that are used by all sub-API's to further decode any response
  returned.

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
  Returns a map containing the *semi*-decoded response from Ripe based on given `url`.

  In case of a successful `t:Tesla.Env.result/0`, the map contains atom keys:
  - `:url`, the url visited
  - `:http`, the https status of the call, (-1 if an error occurred)
  - `:body`, the body of the result
  - `:method`, http method used, usually just `:get`
  - `opts`, any options passed to Tesla (like recv_timeout)

  Note that this might still mean that the endpoint had problems returning
  any useful data.

  In case of any errors, the map contains:
  - `:http`, which is given the value of `-1`
  - `:error`, with some message

  Note:
  - specify a timeout via: `[opts: [recv_timeout: 10_000]]`
  - It's up to the caller to further decode the body of the response.
  - fetch always uses the `Ripe.API.Cache` in order to prevent hammering Ripe unnecessarily.

  ## Examples

  When things go right:

      iex> fetch("www.example.nl")
      ...> |> Map.put(:body, "some html")
      %{
         body: "some html",
         http: 200,
         method: :get,
         opts: [],
         url: "www.example.nl"
      }

  When things go wrong:

      iex> fetch("www.example.nlxyz")
      %{
         error: :nxdomain,
         http: -1,
         url: "www.example.nlxyz",
         opts: []
      }

  When things almost go right:

      iex> fetch("www.example.nl/acdc.txt")
      ...> |> Map.put(:body, "some html")
      %{
        body: "some html",
        http: 404,
        method: :get,
        opts: [],
        url: "www.example.nl/acdc.txt"
      }

  """
  @spec fetch(binary, Keyword.t()) :: map
  def fetch(url, opts \\ []) do
    # Note:
    # - see https://hexdocs.pm/tesla/Tesla.Env.html#content
    # - in case of a timeout, decode cannot add the url, so add it here.
    # [opts: [adapter: [recv_timeout: N]]]
    # {time, opts} = Keyword.pop(opts, :timeout, 2000)
    #
    # opts =
    #   opts
    #   |> Keyword.get(:opts, [])
    #   |> Keyword.put(:adapter, recv_timeout: time)
    #   |> then(fn timeout -> Keyword.put(opts, :opts, timeout) end)

    url = URI.encode(url)

    case Cache.get(url) do
      nil ->
        url
        |> get(opts)
        |> Cache.put(url)

      data ->
        data
    end
    |> decode()
    |> Map.put(:url, url)
    |> Map.put(:opts, Keyword.get(opts, :opts, []))
  end

  @doc """
  In a given `map`, replace map-values by a single value by some given `key`.

  Basically, it will replace a map with the value for given `key` in that map,
  any other keys (and their values) will be lost.  Non-map values, or maps that
  don't have the specified key, remain untouched.

  ## Example

       iex> %{
       ...> "param1" => %{ "value" => "acdc", "I am" => "gone"},
       ...> "param2" => %{ "stays" => "the same"},
       ...> "param3" => "something else"
       ...> }
       ...> |> promote("value")
       %{ "param1" => "acdc",
          "param2" => %{ "stays" => "the same"},
          "param3" => "something else"
       }

  """
  @spec promote(map, binary) :: map
  def promote(map, key) when is_map(map) do
    promoted =
      for {k, v} <- map, is_map(v) and Map.has_key?(v, key), into: %{} do
        {k, Map.get(v, key)}
      end

    Map.merge(map, promoted)
  end

  @doc """
  Moves a nested `key`-value to its outer map, possibly renaming the key and/or
  transforming its value.

  ## Example

      iex> %{
      ...>  "outer" => %{"unique" => 1, "other" => 2},
      ...>  "unique" => "cannot lose this"
      ...> }
      ...> |> move_keyup("unique", rename: "special", transform: fn x -> x + 10 end)
      %{
        "outer" => %{"unique" => 1, "other" => 2 },
        "unique" => "cannot lose this",
        "special" => 11
      }

  """
  @spec move_keyup(map, binary, Keyword.t()) :: map
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
  Reduce a `list` of similar maps to a map by some common `key` that has unique values.

  Each map in the list is added to an accumulator map using the common key's
  value (`map[key]`) as the key in the accumulator map, while also dropping
  `map[key]` from the individual map and adding a `:idx` key,value pair
  that records its original position in the list.

  ## Example

      iex> [
      ...> %{"name" => "attr-name-1", "presence" => "mandatory"},
      ...> %{"name" => "attr-name-2", "presence" => "optional"}
      ...> ]
      ...> |> map_bykey("name")
      %{
        "attr-name-1" => %{:idx => 0, "presence" => "mandatory"},
        "attr-name-2" => %{:idx => 1, "presence" => "optional"}
      }

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
    end
  end
end
