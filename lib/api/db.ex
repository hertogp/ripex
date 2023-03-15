defmodule Ripe.API.DB do
  @moduledoc """
  Decoding of responses for Ripe.API.Db lookup's or searches.
  """

  # A Tesla response looks like:
  #
  # tesla_result: %Tesla.Env{
  #   method: :get,
  #   url: "https://rest.db.ripe.net/ripe/route/131.237.0.0/23AS42894.json",
  #   query: [],
  #   headers: [
  #     {"date", "Tue, 14 Mar 2023 09:34:50 GMT"},
  #     {"content-type", "application/xml"},
  #     {"cache-control", "no-cache, no-store, must-revalidate"},
  #     {"pragma", "no-cache"},
  #     {"expires", "0"},
  #     {"vary", "Accept-Encoding"},
  #     {"content-length", "1263"},
  #     {"server", "Jetty(10.0.12)"}
  #   ],
  #   body: "json-string"
  #   status: 200,
  #   opts: [],
  #   __module__: Ripe.API.DB.Lookup,
  #   __client__: %Tesla.Client{fun: nil, pre: [], post: [], adapter: nil}
  # }

  alias Ripe.API

  @spec decode({:ok | :error, Tesla.Env.result()}) :: {:ok, map} | {:error, {atom, any}}
  def decode({:ok, %Tesla.Env{status: 200} = body}) do
    IO.inspect(body, label: :tesla_result)

    %{
      :api => %{
        :method => body.method,
        :status => body.status,
        :url => body.url,
        :version => API.get_at(body, [:body, "version", "version"])
      },
      :data => decode_objects(body)
    }
  end

  def decode({:ok, %Tesla.Env{status: status, body: body} = response}) do
    cond do
      status >= 100 and status < 103 ->
        {:error, {:informational, status, body}}

      status >= 200 and status < 300 ->
        {:error, {:unsuccessful, status, body}}

      status >= 300 and status < 400 ->
        {:error, {:redirect, status, body}}

      status >= 400 and status < 500 ->
        {:error, {:client, status, response}}

      status >= 500 and status < 600 ->
        {:error, {:server, status, body}}

      true ->
        {:error, {:unknown, status, body}}
    end
  end

  def decode({:error, msg}) do
    {:error, {:http, inspect(msg)}}
  end

  def decode_data(data) do
    data
    |> Map.put(:data, decode_objects(data.data, []))
  end

  def decode_objects(body) do
    body
    |> Ripe.API.get_at([:body, "objects", "object"])
    |> decode_objects([])
  end

  def decode_objects(nil, acc),
    do: acc

  def decode_objects([], acc),
    do: acc

  def decode_objects([obj | tail], acc),
    do: decode_objects(tail, [decode_object(obj) | acc])

  def decode_object(obj) do
    IO.inspect(obj, label: :object)

    obj
    |> Ripe.API.get_at(["attributes", "attribute"])
    |> Ripe.API.map_bykey("name")
    |> Ripe.API.promote("value")
    |> Map.merge(%{
      url: Ripe.API.get_at(obj, ["link", "href"]) <> ".json",
      type: Map.get(obj, "type"),
      primary_key: primary_key(obj)
    })
  end

  defp primary_key(obj) do
    for map <- Ripe.API.get_at(obj, ["primary-key", "attribute"]), into: [] do
      map["value"]
    end
    |> Enum.join()
  end
end
