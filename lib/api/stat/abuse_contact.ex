defmodule Ripe.API.AbuseContact do
  @moduledoc """
  See https://stat.ripe.net/docs/02.data-api/abuse-contact-finder.html
  """

  alias Ripe.API.Stat

  @endpoint "abuse-contact-finder"

  @spec get(integer | binary) :: {:ok, Tesla.Env.t()} | {:error, any}
  def get(asnr) do
    params = [resource: "#{asnr}"]
    Stat.fetch(@endpoint, params)
  end

  def decode(response) do
    case Stat.decode(response) do
      {:error, _} = error -> Stat.error(error, @endpoint)
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
