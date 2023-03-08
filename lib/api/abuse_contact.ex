defmodule Ripe.API.AbuseContact do
  @moduledoc """
  See https://stat.ripe.net/docs/02.data-api/abuse-contact-finder.html
  """

  # {:ok,
  #  %Tesla.Env{
  #    method: :get,
  #    url: "https://stat.ripe.net/data/abuse-contact-finder/data.json?sourceapp=github-ripex&resource=333",
  #    query: [],
  #    headers: [
  #      {"server", "nginx"},
  #      {"date", "Wed, 08 Mar 2023 07:15:26 GMT"},
  #      {"content-type", "application/json; charset=utf-8"},
  #      {"content-length", "764"},
  #      {"connection", "keep-alive"},
  #      {"vary", "Cookie, Accept-Encoding"},
  #      {"access-control-allow-origin", "*"},
  #      {"x-frame-options", "SAMEORIGIN"},
  #      {"x-xss-protection", "1; mode=block"},
  #      {"x-content-type-options", "nosniff"},
  #      {"permissions-policy", "interest-cohort=()"},
  #      {"strict-transport-security", "max-age=31536000; includeSubdomains"}
  #    ],
  #    body: %{
  #      "build_version" => "live.2023.2.1.142",
  #      "cached" => false,
  #      "data" => %{
  #        "abuse_contacts" => ["disa.columbus.ns.mbx.arin-registrations@mail.mil"],
  #        "authoritative_rir" => "arin",
  #        "earliest_time" => "2023-03-08T07:15:26",
  #        "latest_time" => "2023-03-08T07:15:26",
  #        "parameters" => %{"cache" => nil, "resource" => "333"}
  #      },
  #      "data_call_name" => "abuse-contact-finder",
  #      "data_call_status" => "supported",
  #      "messages" => [],
  #      "process_time" => 425,
  #      "query_id" => "20230308071525-c62eeeaf-6917-4e1f-b891-86b2467824bf",
  #      "see_also" => [],
  #      "server_id" => "app133",
  #      "status" => "ok",
  #      "status_code" => 200,
  #      "time" => "2023-03-08T07:15:26.035829",
  #      "version" => "2.1"
  #    },
  #    status: 200,
  #    opts: [],
  #    __module__: Ripe.API,
  #    __client__: %Tesla.Client{fun: nil, pre: [], post: [], adapter: nil}
  #  }}

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
