defmodule Ripe.API.DB.Lookup.Route do
  @moduledoc """
  Rewturns a route obhect by key
  """

  alias Ripe.API.DB.Lookup

  def get(key, asnr) do
    "route"
    |> Lookup.fetch("#{key}#{asnr}")
  end
end
