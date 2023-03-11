defmodule Ripe.API.AsOverview do
  @moduledoc """
  See https://stat.ripe.net/docs/02.data-api/as-overview.html
  """

  alias Ripe.API

  @endpoint "as-overview"

  def get(as) do
    params = [resource: "#{as}"]
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
    |> API.rename(%{"resource" => "asn"})
    |> API.remove(["query_endtime", "query_starttime"])
  end
end
