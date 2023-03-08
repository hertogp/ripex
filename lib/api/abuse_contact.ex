defmodule Ripe.API.AbuseContact do
  @moduledoc """
  See https://stat.ripe.net/docs/02.data-api/abuse-contact-finder.html
  """

  # %Tesla.Env{
  #   method: :get,
  #   url: "https://stat.ripe.net/data/abuse-contact-finder/data.json?sourceapp=github-ripex&resource=42894",
  #   query: [],
  #   headers: [
  #     {"server", "nginx"},
  #     {"date", "Tue, 07 Mar 2023 07:32:50 GMT"},
  #     {"content-type", "application/json; charset=utf-8"},
  #     {"content-length", "739"},
  #     {"connection", "keep-alive"},
  #     {"vary", "Cookie, Accept-Encoding"},
  #     {"access-control-allow-origin", "*"},
  #     {"x-frame-options", "SAMEORIGIN"},
  #     {"x-xss-protection", "1; mode=block"},
  #     {"x-content-type-options", "nosniff"},
  #     {"permissions-policy", "interest-cohort=()"},
  #     {"strict-transport-security", "max-age=31536000; includeSubdomains"}
  #   ],
  #   body: %{
  #     "build_version" => "live.2023.2.1.142",
  #     "cached" => false,
  #     "data" => %{
  #       "abuse_contacts" => ["gilbert.jimenez@rws.nl"],
  #       "authoritative_rir" => "ripe",
  #       "earliest_time" => "2023-03-07T07:32:50",
  #       "latest_time" => "2023-03-07T07:32:50",
  #       "parameters" => %{"cache" => nil, "resource" => "42894"}
  #     },
  #     "data_call_name" => "abuse-contact-finder",
  #     "data_call_status" => "supported",
  #     "messages" => [],
  #     "process_time" => 60,
  #     "query_id" => "20230307073250-c900d25f-a5e2-427e-82d3-26cc51b2cd59",
  #     "see_also" => [],
  #     "server_id" => "app112",
  #     "status" => "ok",
  #     "status_code" => 200,
  #     "time" => "2023-03-07T07:32:50.294954",
  #     "version" => "2.1"
  #   },
  #   status: 200,
  #   opts: [],
  #   __module__: Ripe.API,
  #   __client__: %Tesla.Client{fun: nil, pre: [], post: [], adapter: nil}
  # }

  alias Ripe.API

  @endpoint "abuse-contact-finder"

  @spec get(integer | binary) :: {:ok, Tesla.Env.t()} | {:error, any}
  def get(asnr) do
    params = [resource: "#{asnr}"]
    API.fetch(@endpoint, params)
  end

  def decode({:ok, %Tesla.Env{status: 200, body: body}}) do
    case body["status"] do
      "ok" -> decodep(body["data"])
      _ -> {:error, "oops"}
    end
  end

  def decode({:ok, %Tesla.Env{status: status, body: body}}) do
    API.error(@endpoint, status, body)
  end

  defp decodep(data) do
    %{
      "abuse-contacts" => data["abuse_contacts"],
      "asn" => data["parameters"]["resource"]
    }
  end
end
