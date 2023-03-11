defmodule Ripe.API.Stat.NetworkInfo do
  @moduledoc """
  See https://stat.ripe.net/docs/02.data-api/network-info.html
  """

  alias Ripe.API.Stat

  @endpoint "network-info"

  def get(ip) do
    params = [resource: "#{ip}"]
    Stat.fetch(@endpoint, params)
  end

  def decode(response) do
    case Stat.decode(response) do
      {:error, _} = error -> Stat.error(error, @endpoint)
      data -> data
    end
  end
end
