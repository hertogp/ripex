defmodule Ripe.API.DB.Search.ASN do
  @moduledoc """
  Fetch objects by AS-number

  """

  alias Ripe.API.DB.Search

  @doc """
  Return a list of route objects whose *origin* attribute exactly matches given `ASnumber`.

  Note: asn is formatted as "AS<nr>"
  """
  @spec routes(binary) :: map
  def routes(asn) do
    asn
    |> Search.fetch([{"inverse-attribute", "origin"}])
    |> Search.decode()
    |> Map.get("objects")
    |> Map.get("object")
  end

  def mntner(asn) do
    asn
    |> Search.fetch()
    |> Search.decode()
  end
end
