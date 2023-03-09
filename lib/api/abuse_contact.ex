defmodule Ripe.API.AbuseContact do
  @moduledoc """
  See https://stat.ripe.net/docs/02.data-api/abuse-contact-finder.html
  """

  alias Ripe.API

  @endpoint "abuse-contact-finder"

  @spec get(integer | binary) :: {:ok, Tesla.Env.t()} | {:error, any}
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
      "resource" => data["parameters"]["resource"],
      "abuse-contacts" => data["abuse_contacts"]
    }
  end
end
