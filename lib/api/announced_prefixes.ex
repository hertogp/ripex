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

  def decode(response) do
    case API.decode(response) do
      {:error, _} = error -> API.error(error, @endpoint)
      data -> decodep(data)
    end
  end

  defp decodep(data) do
    %{
      "resource" => data["resource"],
      "prefixes" => Enum.reduce(data["prefixes"], [], fn elm, acc -> [elm["prefix"] | acc] end)
    }
    |> then(fn m -> Map.put(m, "count", length(m["prefixes"])) end)
  end
end
