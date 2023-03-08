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

  defp encode(endpoint, params) do
    params
    |> List.insert_at(0, @sourceapp)
    |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
    |> Enum.join("&")
    |> then(fn query -> "#{endpoint}/data.json?#{query}" end)
  end

  # API

  def fetch(endpoint, params) do
    endpoint
    |> encode(params)
    |> get()
  end

  def error(endpoint, status, body) do
    {:error, {endpoint, status, body}}
  end
end
