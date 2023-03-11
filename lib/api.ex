defmodule Ripe.API do
  @moduledoc """
  See https://stat.ripe.net/docs/02.data-api/
  - https://stat.ripe.net/data/<name>/data.json?param1=value1&param2=value2&...

  """

  # TODO:
  # - parameterize timeout` since as-routing-consistency on 1136 times out
  # - put body["version"] into body's data so decoders can use it (or not)
  # - check data_call_status, anything else than "supported - .." is an error
  #   (especially "maintenance - ..." which means no info was retrieved)
  # - add whois client to retrieve contact information, e.g. via
  #   https://rest.db.ripe.net/{source}/{object-type}/{key}.json
  #   see https://apps-test.db.ripe.net/docs/06.Update-Methods/01-RESTful-API.html#restful-uri-format
  #   Alternative format seems to be:
  #   https://rest.db.ripe.net/search.json?query-string=2a04:9a02:1800::/37
  #   `-> see https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html#rest-api-search
  # - examples
  #   https://rest.db.ripe.net/search.json?flags=M&query-string=1.2.0.0/16

  use Tesla

  @base_url "https://stat.ripe.net/data/"
  @sourceapp {:sourceapp, "github-ripex"}

  plug(Tesla.Middleware.BaseUrl, @base_url)
  plug(Tesla.Middleware.JSON)

  # Helpers

  defp msg_bytag(tag, map) when is_map(map) do
    msg_bytag(tag, Map.get(map, "messages", []))
  end

  defp msg_bytag(tag, []) do
    "#{tag} - no message info found"
  end

  defp msg_bytag(_bytag, [[tag, msg]]) do
    "#{tag} - #{msg}"
  end

  defp msg_bytag(bytag, [[tag, msg] | tail]) do
    # get first message by given tag
    tag = String.downcase(tag)

    if String.starts_with?(tag, bytag) do
      # bytag == String.downcase(tag) do
      "#{tag} - #{msg}"
    else
      msg_bytag(bytag, tail)
    end
  end

  # API

  def url(endpoint, params) do
    params
    |> List.insert_at(0, @sourceapp)
    |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
    |> Enum.join("&")
    |> then(fn query -> "#{endpoint}/data.json?#{query}" end)
  end

  def fetch(endpoint, params) do
    endpoint
    |> url(params)
    |> get()
  end

  # generic check on successful response
  # - return either data block OR error-tuple
  def decode({:ok, %Tesla.Env{status: 200, body: body}}) do
    # todo:
    # - also check body["data_call_status"] and report if other than "supported"
    # - in debug mode, log method, url, status
    # - treat a non-existing endpoint as an error (response is ok, data empty)
    # - add data_call_status, data_call_name, version to returned data map (for the decoders)
    #   or maybe simply return the body?
    case body["status"] do
      "ok" -> body["data"]
      status -> {:error, {:endpoint, status, msg_bytag(status, body)}}
    end
  end

  def decode({:ok, %Tesla.Env{status: status, body: body}}) do
    cond do
      status >= 100 and status < 103 ->
        {:error, {:informational, status, msg_bytag("error", body)}}

      status >= 200 and status < 300 ->
        {:error, {:unsuccessful, status, msg_bytag("error", body)}}

      status >= 300 and status < 400 ->
        {:error, {:redirect, status, msg_bytag("error", body)}}

      status >= 400 and status < 500 ->
        {:error, {:client, status, msg_bytag("error", body)}}

      status >= 500 and status < 600 ->
        {:error, {:server, status, msg_bytag("error", body)}}

      true ->
        {:error, {:unknown, status, msg_bytag("error", body)}}
    end
  end

  def decode({:error, msg}) do
    {:error, msg}
  end

  def error({:error, {code, status, body}}, endpoint),
    do: {:error, {code, status, endpoint, body}}

  def error({:error, :timeout}, endpoint),
    do: {:error, {:server, :timeout, endpoint}, "timeout"}

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

  Each map in the list is added to an accumulator map
  using `map[key]` as key while also dropping `map[key]`
  from the individual map.

  """
  @spec map_bykey(list, binary) :: map
  def map_bykey(list, key) when is_list(list) do
    for map <- list, Map.has_key?(map, key), into: %{} do
      {map[key], Map.delete(map, key)}
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
