defmodule Ripe.API.Stat do
  @moduledoc """
  See https://stat.ripe.net/docs/02.data-api/
  - https://stat.ripe.net/data/<name>/data.json?param1=value1&param2=value2&...

  """

  # TODO:
  # - parameterize timeout` since as-routing-consistency on 1136 times out
  # - put body["version"] into body's data so decoders can use it (or not)
  # - check data_call_status, anything else than "supported - .." is an error
  #   (especially "maintenance - ..." which means no info was retrieved)
  # - add whois client to retrieve contact information, e.g. via
  #   https://rest.db.ripe.net/{source}/{object-type}/{key}.json
  #   see https://apps-test.db.ripe.net/docs/06.Update-Methods/01-RESTful-API.html#restful-uri-format
  #   Alternative format seems to be:
  #   https://rest.db.ripe.net/search.json?query-string=2a04:9a02:1800::/37
  #   `-> see https://apps.db.ripe.net/docs/11.How-to-Query-the-RIPE-Database/03-RESTful-API-Queries.html#rest-api-search
  # - examples
  #   https://rest.db.ripe.net/search.json?flags=M&query-string=1.2.0.0/16

  use Tesla

  @base_url "https://stat.ripe.net/data/"
  @sourceapp {:sourceapp, "github-ripex"}

  plug(Tesla.Middleware.BaseUrl, @base_url)
  plug(Tesla.Middleware.JSON)

  # Helpers

  defp msg_bytag(tag, map) when is_map(map) do
    msg_bytag(tag, Map.get(map, "messages", []))
  end

  defp msg_bytag(tag, []) do
    "#{tag} - no message info found"
  end

  defp msg_bytag(_bytag, [[tag, msg]]) do
    "#{tag} - #{msg}"
  end

  defp msg_bytag(bytag, [[tag, msg] | tail]) do
    # get first message by given tag
    tag = String.downcase(tag)

    if String.starts_with?(tag, bytag) do
      # bytag == String.downcase(tag) do
      "#{tag} - #{msg}"
    else
      msg_bytag(bytag, tail)
    end
  end

  defp url(endpoint, params \\ []) do
    # note: we always have at least one param: @sourceapp
    params
    |> List.insert_at(0, @sourceapp)
    |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
    |> Enum.join("&")
    |> then(fn query -> "#{endpoint}/data.json?#{query}" end)
  end

  # generic check on successful response
  # - return either data block OR error-tuple
  defp decode({:ok, %Tesla.Env{status: 200, body: body}}) do
    # todo:
    # - also check body["data_call_status"] and report if other than "supported"
    # - in debug mode, log method, url, status
    # - treat a non-existing endpoint as an error (response is ok, data empty)
    # - add data_call_status, data_call_name, version to returned data map (for the decoders)
    #   or maybe simply return the body?
    case body["status"] do
      "ok" -> body["data"]
      status -> {:error, {:endpoint, status, msg_bytag(status, body)}}
    end
  end

  defp decode({:ok, %Tesla.Env{status: status, body: body}}) do
    cond do
      status >= 100 and status < 103 ->
        {:error, {:informational, status, msg_bytag("error", body)}}

      status >= 200 and status < 300 ->
        {:error, {:unsuccessful, status, msg_bytag("error", body)}}

      status >= 300 and status < 400 ->
        {:error, {:redirect, status, msg_bytag("error", body)}}

      status >= 400 and status < 500 ->
        {:error, {:client, status, msg_bytag("error", body)}}

      status >= 500 and status < 600 ->
        {:error, {:server, status, msg_bytag("error", body)}}

      true ->
        {:error, {:unknown, status, msg_bytag("error", body)}}
    end
  end

  defp decode({:error, msg}) do
    {:error, msg}
  end

  # defp error({:error, :timeout}, endpoint),
  #   do: {:error, {:server, :timeout, endpoint}, "timeout"}

  # API

  @doc """
  See https://stat.ripe.net/docs/02.data-api/announced-prefixes.html
  """
  def announced_prefixes(asnr) do
    "announced-prefixes"
    |> url([{"resource", "#{asnr}"}])
    |> get()
    |> decode()
  end

  @doc """
  See https://stat.ripe.net/docs/02.data-api/network-info.html
  """
  def network_info(ip) do
    "network-info"
    |> url([{"resource", "#{ip}"}])
    |> get()
    |> decode()
  end

  @doc """
  See https://stat.ripe.net/docs/02.data-api/abuse-contact-finder.html
  """
  def abuse_c(asnr) do
    "abuse-contact-finder"
    |> url([{"resource", "#{asnr}"}])
    |> get()
    |> decode()
  end

  @doc """
  See https://stat.ripe.net/docs/02.data-api/as-overview.html
  """
  def as_overview(asnr) do
    "as-overview"
    |> url([{"resource", "#{asnr}"}])
    |> get()
    |> decode()
  end

  @doc """
  See https://stat.ripe.net/docs/02.data-api/as-routing-consistency.html
  """
  def as_routing(asnr) do
    "as-routing-consistency"
    |> url([{"resource", "#{asnr}"}])
    |> get()
    |> decode()
    |> (&Map.put(&1, "prefixes", Ripe.API.map_bykey(&1["prefixes"], "prefix"))).()
  end

  @doc """
  See https://stat.ripe.net/docs/02.data-api/prefix-overview.html
  """
  def prefix_overview(ip) do
    "prefix-overview"
    |> url([{"resource", "#{ip}"}])
    |> get()
    |> decode()
  end

  @doc """
  See https://stat.ripe.net/docs/02.data-api/rpki-validation.html

  """
  def rpki_validation(asnr, prefix) do
    "rpki-validation"
    |> url([{"resource", "#{asnr}"}, {"prefix", "#{prefix}"}])
    |> get()
    |> decode()
  end
end
