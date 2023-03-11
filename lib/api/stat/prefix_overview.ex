defmodule Ripe.API.Stat.PrefixOverview do
  @moduledoc """
  See https://stat.ripe.net/docs/02.data-api/prefix-overview.html
  """

  alias Ripe.API
  alias Ripe.API.Stat

  @endpoint "prefix-overview"

  def get(ip) do
    params = [resource: "#{ip}"]
    Stat.fetch(@endpoint, params)
  end

  def decode(response) do
    case Stat.decode(response) do
      {:error, _} = error -> Stat.error(error, @endpoint)
      data -> decodep(data)
    end
  end

  defp decodep(data) do
    data
    |> API.rename(%{"resource" => "prefix"})
  end
end
