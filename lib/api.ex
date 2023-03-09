defmodule Ripe.API do
  @moduledoc """
  See https://stat.ripe.net/docs/02.data-api/
  - https://stat.ripe.net/data/<name>/data.json?param1=value1&param2=value2&...
  -
  """

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
end
