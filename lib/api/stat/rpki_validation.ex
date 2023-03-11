defmodule Ripe.API.RpkiValidation do
  @moduledoc """
  See https://stat.ripe.net/docs/02.data-api/rpki-validation.html

  """

  alias Ripe.API
  alias Ripe.API.Stat

  @endpoint "rpki-validation"

  def get(asnr, prefix) do
    params = [resource: "#{asnr}", prefix: "#{prefix}"]
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
    |> API.rename(%{"resource" => "asn", "origin" => "asn"})
    |> API.remove(["validator", "validity"])
  end
end
