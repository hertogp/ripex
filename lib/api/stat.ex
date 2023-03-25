defmodule Ripe.API.Stat do
  @moduledoc """
  See https://stat.ripe.net/docs/02.data-api/
  - https://stat.ripe.net/data/<name>/data.json?param1=value1&param2=value2&...

  ## datastructure returned
  See https://stat.ripe.net/docs/02.data-api/#output-data-structure

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

  alias Ripe.API

  @base_url "https://stat.ripe.net/data"
  @sourceapp {:sourceapp, "github-ripex"}

  plug(Tesla.Middleware.BaseUrl, @base_url)
  plug(Tesla.Middleware.Headers, [{"accept", "application/json"}])
  plug(Tesla.Middleware.JSON)

  # Helpers

  defp decode(result) do
    # todo:
    # - also check body["data_call_status"] and report if other than "supported"
    #   `-> also just take first word of the binary
    # - in debug mode, log method, url, status
    # - treat a non-existing endpoint as an error (response is ok, data empty)
    # - add data_call_status, data_call_name, version to returned data map (for the decoders)
    #   or maybe simply return the body?
    result
    |> Map.put(:source, __MODULE__)
    |> API.move_keyup("version")
    |> API.move_keyup("data_call_name", rename: "call_name")
    |> API.move_keyup("data_call_status", rename: "call_status")
    |> API.move_keyup("status")
    |> API.move_keyup("data")
    |> API.move_keyup("messages", transform: &decode_messages/1)
    |> Map.delete(:body)
  end

  defp decode_messages(list) do
    list
    |> Enum.reduce(%{}, fn [k, v], acc ->
      case acc[k] do
        nil -> Map.put(acc, k, v)
        val -> Map.put(acc, k, val <> "\n" <> v)
      end
    end)
  end

  def url(endpoint, params) do
    # TODO make private
    params
    |> List.insert_at(0, @sourceapp)
    |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
    |> Enum.join("&")
    |> then(fn query -> "#{@base_url}/#{endpoint}/data.json?#{query}" end)
  end

  # API

  def announced_prefixes(asnr) do
    "announced-prefixes"
    |> url([{"resource", "#{asnr}"}])
    |> API.fetch(opts: [recv_timeout: 10_000])
    |> decode()
    |> API.move_keyup("prefixes",
      transform: fn l -> Enum.reduce(l, fn m, acc -> [Map.get(m, "prefix") | acc] end) end
    )
  end

  @doc """
  See https://stat.ripe.net/docs/02.data-api/network-info.html
  """
  def network_info(ip) do
    "network-info"
    |> url([{"resource", "#{ip}"}])
    |> API.fetch()
    |> decode()
    |> API.move_keyup("asns")
    |> API.move_keyup("prefix")
    |> Map.delete("data")
  end

  @doc """
  See https://stat.ripe.net/docs/02.data-api/abuse-contact-finder.html
  """
  def abuse_c(asnr) do
    "abuse-contact-finder"
    |> url([{"resource", "#{asnr}"}])
    |> API.fetch()
    |> decode()
    |> API.move_keyup("abuse_contacts")
    |> API.move_keyup("authoritative_rir")
    |> Map.delete("data")
  end

  @doc """
  See https://stat.ripe.net/docs/02.data-api/as-overview.html
  """
  def as_overview(asnr) do
    "as-overview"
    |> url([{"resource", "#{asnr}"}])
    |> API.fetch()
    |> decode()
    |> API.move_keyup("announced")
    |> API.move_keyup("holder")
    |> API.move_keyup("block")
    |> API.move_keyup("resource", rename: "asn")
    |> API.move_keyup("type", rename: "asn")
    |> Map.delete("data")
  end

  @doc """
  See https://stat.ripe.net/docs/02.data-api/as-routing-consistency.html
  """
  def as_routing(asnr) do
    # try 1136 to see a timeout with 10_0000 default timeout
    "as-routing-consistency"
    |> url([{"resource", "#{asnr}"}])
    |> API.fetch()
    |> decode()
    |> API.move_keyup("imports")
    |> API.move_keyup("exports")
    |> API.move_keyup("prefixes", transform: fn l -> API.map_bykey(l, "prefix") end)
    |> API.move_keyup("authority")
    |> API.move_keyup("resource", rename: "asn")
    |> Map.delete("data")
  end

  @doc """
  See https://stat.ripe.net/docs/02.data-api/prefix-overview.html
  """
  def prefix_overview(ip) do
    "prefix-overview"
    |> url([{"resource", "#{ip}"}])
    |> API.fetch()
    |> decode()
    |> API.move_keyup("resource", rename: "prefix")
    |> API.move_keyup("actual_num_related")
    |> API.move_keyup("announced")
    |> API.move_keyup("asns", transform: fn l -> API.map_bykey(l, "asn") end)
    |> API.move_keyup("block")
    |> API.move_keyup("is_less_specific")
    |> API.move_keyup("actual_num_related")
    |> API.move_keyup("num_filtered_out")
    |> API.move_keyup("related_prefixes")
    |> API.move_keyup("resource", rename: "prefix")
    |> Map.delete("data")
  end

  @doc """
  See https://stat.ripe.net/docs/02.data-api/rpki-validation.html

  """
  def rpki_validation(asnr, prefix) do
    # todo: turn roa into "prefix^maxlength@AS-nr"
    "rpki-validation"
    |> url([{"resource", "#{asnr}"}, {"prefix", "#{prefix}"}])
    |> API.fetch()
    |> decode()
    |> API.move_keyup("prefix")
    |> API.move_keyup("resource", rename: "asn")
    |> API.move_keyup("status", rename: "rpki_status")
    |> API.move_keyup("validating_roas")
    |> API.move_keyup("validator")
    |> Map.delete("data")
  end

  @doc """
  Returns a map like `Ripe.API.Stat.as_routing/1` with `rpki` status added for each prefix.
  """
  def as_rpki(asnr) do
    asnr
    |> as_routing()
    |> update_in(["prefixes"], fn map ->
      for {pfx, attrs} <- map, into: %{} do
        rpki = rpki_validation(asnr, pfx)
        roas = Enum.filter(rpki["validating_roas"], fn roa -> roa["validity"] == "valid" end)
        pki_attrs = %{"rpki" => rpki["rpki_status"], "roas" => roas}

        {pfx, Map.merge(attrs, pki_attrs)}
      end
    end)
    |> update_in(["call_name"], fn name -> name <> " + rpki_validation" end)
  end
end
