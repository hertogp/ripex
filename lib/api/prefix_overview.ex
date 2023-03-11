defmodule Ripe.API.PrefixOverview do
  @moduledoc """
  See https://stat.ripe.net/docs/02.data-api/prefix-overview.html
  """

  alias Ripe.API

  @endpoint "prefix-overview"

  def get(ip) do
    params = [resource: "#{ip}"]
    API.fetch(@endpoint, params)
  end

  def decode(response) do
    case API.decode(response) do
      {:error, _} = error -> API.error(error, @endpoint)
      data -> decodep(data)
    end
  end

  defp decodep(data) do
    data
    |> API.rename(%{"resource" => "prefix"})
  end
end
