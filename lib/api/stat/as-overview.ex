defmodule Ripe.API.Stat.AsOverview do
  @moduledoc """
  See https://stat.ripe.net/docs/02.data-api/as-overview.html
  """

  alias Ripe.API
  alias Ripe.API.Stat

  @endpoint "as-overview"

  def get(as) do
    params = [resource: "#{as}"]
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
    |> API.rename(%{"resource" => "asn"})
    |> API.remove(["query_endtime", "query_starttime"])
  end
end
