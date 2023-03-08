defmodule Ripe.API.RpkiValidation do
  @moduledoc """
  See https://stat.ripe.net/docs/02.data-api/rpki-validation.html
  """

  alias Ripe.API

  @endpoint "rpki-validation"

  def get(asnr, prefix) do
    params = [resource: "#{asnr}", prefix: "#{prefix}"]
    API.fetch(@endpoint, params)
  end
end
