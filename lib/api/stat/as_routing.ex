defmodule Ripe.API.Stat.AsRoutingConsistency do
  @moduledoc """
  See https://stat.ripe.net/docs/02.data-api/as-routing-consistency.html
  """

  alias Ripe.API
  alias Ripe.API.Stat

  @endpoint "as-routing-consistency"

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
    |> API.remove(["query_starttime", "query_endtime", "cache", "query_time"])
    |> update_in(["prefixes"], &API.map_bykey(&1, "prefix"))
  end
end
