defmodule Ripe.API.AnnouncedPrefixes do
  @moduledoc """
  See https://stat.ripe.net/docs/02.data-api/announced-prefixes.html
  """

  alias Ripe.API

  @endpoint "announced-prefixes"

  def get(asnr) do
    params = [resource: "#{asnr}"]
    API.fetch(@endpoint, params)
  end

  def decode({:ok, %Tesla.Env{status: 200, body: body}}) do
    case body["status"] do
      "ok" -> decodep(body["data"])
      _ -> {:error, "oops"}
    end
  end

  defp decodep(data) do
    IO.inspect(data)
  end
end
