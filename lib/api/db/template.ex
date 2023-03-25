defmodule Ripe.API.DB.Template do
  @moduledoc """
  Functions to retrieve RIPE DB templates.



  """

  @base_url "https://rest.db.ripe.net/metadata/templates"

  use Tesla

  alias Ripe.API
  alias Ripe.API.DB

  plug(Tesla.Middleware.BaseUrl, @base_url)
  plug(Tesla.Middleware.Headers, [{"accept", "application/json"}])
  plug(Tesla.Middleware.JSON)

  # Helpers

  defp decode(%{source: Ripe.API.DB.Template} = result) do
    # Template returns only one object with its own encoding
    data_path = [:body, "templates", "template", 0]

    attrs =
      result
      |> API.get_at(data_path ++ ["attributes", "attribute"])
      |> API.map_bykey("name")

    result
    |> Map.put(:rir, API.get_at(result, data_path ++ ["source"])["id"])
    |> Map.put(:type, API.get_at(result, data_path ++ ["type"]))
    |> Map.put(
      :primary_keys,
      DB.collect_keys_byvalue(attrs, fn m -> "PRIMARY_KEY" in Map.get(m, "keys", []) end)
    )
    |> Map.put(
      :inverse_keys,
      DB.collect_keys_byvalue(attrs, fn m -> "INVERSE_KEY" in Map.get(m, "keys", []) end)
    )
    |> Map.put(
      :lookup_keys,
      DB.collect_keys_byvalue(attrs, fn m -> "LOOKUP_KEY" in Map.get(m, "keys", []) end)
    )
    |> Map.delete(:body)
    |> Map.merge(attrs)
  end

  @spec url(binary) :: binary
  defp url(object) do
    "#{@base_url}/#{object}.json"
  end

  # API

  @doc """
  Fetch the Ripe template for given `object`.

  """
  @spec fetch(binary) :: map
  def fetch(object) do
    object
    |> url()
    |> API.fetch()
    |> Map.put(:source, __MODULE__)
    |> decode()
  end
end
