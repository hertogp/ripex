defmodule Ripe.API.NetworkInfo do
  @moduledoc """
  See https://stat.ripe.net/docs/02.data-api/rpki-validation.html
  """

  alias Ripe.API

  @endpoint "network-info"

  def get(ip) do
    params = [resource: "#{ip}"]
    API.fetch(@endpoint, params)
  end

  def decode(response) do
    case API.decode(response) do
      {:error, _} = error -> API.error(error, @endpoint)
      data -> data
    end
  end
end
