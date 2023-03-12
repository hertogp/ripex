defmodule Ripe.API.DB.Lookup.Route do
  @moduledoc """
  Returns a route obhect by key
  """

  alias Ripe.API.DB.Lookup

  def get(key, asnr) do
    "route"
    |> Lookup.url("#{key}#{asnr}")
    |> Lookup.fetch()
  end
end
