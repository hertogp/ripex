defmodule Ripe.API.Stat do
  @moduledoc """
  Functions to retrieve information from the [RIPEstat API](https://stat.ripe.net/docs/02.data-api/).

  The basic url used is:

  ```text
  https://stat.ripe.net/data/<endpoint>/data.json?param1=value1&param2=value2&...
  ```

  The `fetch/2` function can be used to access any
  [endpoint](https://stat.ripe.net/docs/02.data-api/#ripestat-data-api) and decodes
  the result to a map (also in case of errors).

  For some of the endpoints, the results are decoded in order to have a more
  manageable datastructure.  These include:

  - [announced-prefixes](https://stat.ripe.net/docs/02.data-api/announced-prefixes.html)
  - [network-info](https://stat.ripe.net/docs/02.data-api/network-info.html)
  - [abuse-contact-finder](https://stat.ripe.net/docs/02.data-api/abuse-contact-finder.html)
  - [as-overview](https://stat.ripe.net/docs/02.data-api/as-overview.html)
  - [as-routing-consistency](https://stat.ripe.net/docs/02.data-api/as-routing-consistency.html)
  - [prefix-overview](https://stat.ripe.net/docs/02.data-api/prefix-overview.html)
  - [rpki-validation](https://stat.ripe.net/docs/02.data-api/rpki-validation.html)

  Other endpoints will simply yield the json decoded results.

  The `rpki/2` function was added as a convenience and it combines the results two
  endpoints,


  """

  # TODO:
  # - parameterize timeout` since as-routing-consistency on 1136 times out
  # - put body["version"] into body's data so decoders can use it (or not)
  # - check data_call_status, anything else than "supported - .." is an error
  #   (especially "maintenance - ..." which means no info was retrieved)
  # - add whois client to retrieve contact information, e.g. via
  #   https://rest.db.ripe.net/{source}/{object-type}/{key}.json
  #   see https://apps-test.db.ripe.net/docs/06.Update-Methods/01-RESTful-API.html#restful-uri-format
  # - Normalize xxxx to ASxxxx for AS-numbers
  # - use source: "Ripe.API.Stat.function" (as a string) (maybe create nx decode for that?)

  use Tesla, only: [:get], docs: false

  alias Ripe.API

  @base_url "https://stat.ripe.net/data"
  @sourceapp {:sourceapp, "github-ripex"}

  plug(Tesla.Middleware.BaseUrl, @base_url)
  plug(Tesla.Middleware.Headers, [{"accept", "application/json"}])
  plug(Tesla.Middleware.JSON)

  # Helpers

  defp decode(%{http: 200, source: "Ripe.API.Stat.announced-prefixes"} = result) do
    result
    |> API.move_keyup("prefixes",
      transform: fn l -> Enum.reduce(l, [], fn m, acc -> [Map.get(m, "prefix") | acc] end) end
    )
    |> Map.delete("data")
  end

  defp decode(%{http: 200, source: "Ripe.API.Stat.network-info"} = result) do
    result
    |> API.move_keyup("asns")
    |> API.move_keyup("prefix")
    |> Map.delete("data")
  end

  defp decode(%{http: 200, source: "Ripe.API.Stat.abuse-contact-finder"} = result) do
    result
    |> API.move_keyup("abuse_contacts", rename: "abuse-c")
    |> API.move_keyup("authoritative_rir", rename: "rir")
    |> Map.delete("data")
  end

  defp decode(%{http: 200, source: "Ripe.API.Stat.as-overview"} = result) do
    result
    |> API.move_keyup("announced")
    |> API.move_keyup("holder")
    |> API.move_keyup("block")
    |> API.move_keyup("resource", rename: "asn")
    |> API.move_keyup("type")
    |> Map.delete("data")
  end

  defp decode(%{http: 200, source: "Ripe.API.Stat.as-routing-consistency"} = result) do
    result
    |> API.move_keyup("imports")
    |> API.move_keyup("exports")
    |> API.move_keyup("prefixes", transform: fn l -> API.map_bykey(l, "prefix") end)
    |> API.move_keyup("authority")
    |> API.move_keyup("resource", rename: "asn")
    |> Map.delete("data")
  end

  defp decode(%{http: 200, source: "Ripe.API.Stat.prefix-overview"} = result) do
    result
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

  defp decode(%{http: 200, source: "Ripe.API.Stat.rpki-validation"} = result) do
    result
    |> API.move_keyup("prefix")
    |> API.move_keyup("resource", rename: "asn")
    |> API.move_keyup("status", rename: "rpki_status")
    |> API.move_keyup("validating_roas")
    |> API.move_keyup("validator")
    |> Map.delete("data")
  end

  defp decode(%{http: -1} = result) do
    # error, probably due to timeout
    result
  end

  # cath all: simply return the result without any decoding
  defp decode(result) do
    if result.http == 200 do
      result
    else
      # probably an error
      reason =
        result["messages"]
        |> Map.values()
        |> Enum.join("\n")

      result
      |> Map.put(:error, reason)
    end
  end

  defp decode_messages(list) do
    # concatenate messages per message-type
    list
    |> Enum.reduce(%{}, fn [type, msg], acc ->
      case acc[type] do
        nil -> Map.put(acc, type, msg)
        val -> Map.put(acc, type, "#{val}\n#{msg}")
      end
    end)
  end

  defp url(endpoint, params) do
    params
    |> List.insert_at(0, @sourceapp)
    |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
    |> Enum.join("&")
    |> then(fn query -> "#{@base_url}/#{endpoint}/data.json?#{query}" end)
  end

  # API

  @doc """
  Retrieve information from a given RIPEstat `endpoint`, possibly decoding its results.

  The `endpoint` parameter should correspond to a valid endpoint listed at the
  [RIPEstat API](https://stat.ripe.net/docs/02.data-api/), while
  `params` is a `t:Keyword.t/0` list and depends on the endpoint being accessed.


  Optionally, `params` may include a Ripex-specific `timeout: N` option to wait
  N milliseconds instead of the default 2000 ms.  This is dropped from `params`,
  before forming the url to visit.

  In case of success, the result is a map with atom keys that include:
  - `http:` - the http return code
  - `method`: - always `:get`
  - `opts` - options passed on to the http client
  - `source` - "Ripe.API.Stat." <> endpoint

  and some binary keys that are lifted from the repsonse's `:body` into the outer map:
  - "version" - which lists the endpoint's version
  - "call_name" - which originally was called "data_call_name"
  - "call_status" - which originally was call "data_call_name" and is limited to its first word.
  - "status" - status of the call's result
  - "messages" - which may indicate additional info and/or error messages
  - "data" - which is the actual endpoint data returned.

  In case of success, some endpoints will have the "data" decoded further.
  There are *a lot* of endpoints, so for most endpoints the caller needs to
  decode the "data" field herself.

  In case of an error, an `:error` field is added which is all the lines in
  "messages" field joined by a newline and no further decoding takes place.

  ## Examples

  The [rir](https://stat.ripe.net/docs/02.data-api/rir.html#rir) endpoint takes a
  an ip prefix/address as a `resource` and optionally a `starttime`, `endtime`
  and `lod` (level of detail). Its `data` field is not decoded.

      iex> fetch("rir", resource: "94.198.159.35")
      %{
        :http => 200,
        :method => :get,
        :opts => [recv_timeout: 2000],
        :source => "Ripe.API.Stat.rir",
        :url => "https://stat.ripe.net/data/rir/data.json?sourceapp=github-ripex&resource=94.198.159.35",
        "call_name" => "rir",
        "call_status" => "supported",
        "data" => %{
          "latest" => "2023-04-07T00:00:00",
          "lod" => 1,
          "query_endtime" => "2023-04-07T00:00:00",
          "query_starttime" => "2023-04-07T00:00:00",
          "resource" => "94.198.159.35/32",
          "rirs" => [%{"first_time" => "2023-04-07T00:00:00", "last_time" => "2023-04-07T00:00:00", "rir" => "RIPE NCC"}]
        },
        "messages" => %{"info" => "IP address has been converted to a prefix"},
        "status" => "ok",
        "version" => "0.1"
      }

  If an endpoint does not exist, RIPE will happily inform you about that,
  the `call_status` is "supported"  and `status` is "ok" (oddly enough).

      iex> fetch("iri", resource: "94.198.159.35")
      %{
        :http => 200,
        :method => :get,
        :opts => [recv_timeout: 2000],
        :source => "Ripe.API.Stat.iri",
        :url => "https://stat.ripe.net/data/iri/data.json?sourceapp=github-ripex&resource=94.198.159.35",
        "call_name" => "iri",
        "call_status" => "supported",
        "data" => %{},
        "messages" => %{
          "info" => "This data call does not exist on RIPEstat. See https://stat.ripe.net/docs/data_api for available data calls."
        },
        "status" => "ok",
        "version" => "1.0"
      }

  If however, a parameter is inappropriate if will report an error:

      iex> fetch("rir", resource: "oops")
      %{
        :error => "oops is of an unsupported resource type. It should be an asn or IP prefix/range/address.",
        :http => 400,
        :method => :get,
        :opts => [recv_timeout: 2000],
        :source => "Ripe.API.Stat.rir",
        :url => "https://stat.ripe.net/data/rir/data.json?sourceapp=github-ripex&resource=oops",
        "call_name" => "rir",
        "call_status" => "supported",
        "data" => %{},
        "messages" => %{"error" => "oops is of an unsupported resource type. It should be an asn or IP prefix/range/address."},
        "status" => "error",
        "version" => "0.1"
      }


  The [abuse-contact-finder](https://stat.ripe.net/docs/02.data-api/abuse-contact-finder.html)
  takes a single `resource` parameter whose value can be an IP address, prefix or an AS number.

      iex> fetch("abuse-contact-finder", resource: "94.198.159.35")
      %{
        :http => 200,
        :method => :get,
        :opts => [recv_timeout: 2000],
        :source => "Ripe.API.Stat.abuse-contact-finder",
        :url => "https://stat.ripe.net/data/abuse-contact-finder/data.json?sourceapp=github-ripex&resource=94.198.159.35",
        "abuse-c" => ["abuse@sidn.nl"],
        "call_name" => "abuse-contact-finder",
        "call_status" => "supported",
        "messages" => %{},
        "rir" => "ripe",
        "status" => "ok",
        "version" => "2.1"
      }


  Other endpoints that have their `data` field encoded, include:
  - [announced-prefixes](https://stat.ripe.net/docs/02.data-api/announced-prefixes.html)
  - [as-overview](https://stat.ripe.net/docs/02.data-api/as-overview.html)
  - [as-routing-consistency](https://stat.ripe.net/docs/02.data-api/as-routing-consistency.html)
  - [network-info](https://stat.ripe.net/docs/02.data-api/network-info.html)
  - [prefix-overview](https://stat.ripe.net/docs/02.data-api/prefix-overview.html)
  - [rpki-validation](https://stat.ripe.net/docs/02.data-api/rpki-validation.html)

  """
  @spec fetch(binary, Keyword.t()) :: map
  def fetch(endpoint, params \\ []) do
    {time, params} = Keyword.pop(params, :timeout, 2000)
    timeout = [opts: [recv_timeout: time]]
    first_word = fn str -> String.split(str) |> hd() end

    endpoint
    |> url(params)
    |> API.fetch(timeout)
    |> Map.put(:source, "Ripe.API.Stat.#{endpoint}")
    |> API.move_keyup("version")
    |> API.move_keyup("data_call_name", rename: "call_name")
    |> API.move_keyup("data_call_status", rename: "call_status", transform: first_word)
    |> API.move_keyup("status")
    |> API.move_keyup("data")
    |> API.move_keyup("messages", transform: &decode_messages/1)
    |> Map.delete(:body)
    |> decode()
  end

  @doc """
  Returns a map with bgp/whois/rpki-information on the routes announced by given `as`.

  `rpki` takes an ASnr as a single parameter, consults the
   [as-routing-consistency](https://stat.ripe.net/docs/02.data-api/as-routing-consistency.html)
   and performs an
   [rpki-validation](https://stat.ripe.net/docs/02.data-api/rpki-validation.html)
   for each prefix found, updating the information accordingly.

  ## Example

      iex> rpki("AS1140")
      ...> |> Map.get("prefixes")
      ...> |> Map.get("185.76.132.0/22")
      %{
        :idx => 1,
        "in_bgp" => true,
        "in_whois" => true,
        "irr_sources" => ["RIPE"],
        "roas" => [%{
          "max_length" => 22,
          "origin" => "1140",
          "prefix" => "185.76.132.0/22",
          "validity" => "valid"
        }],
        "rpki" => "valid"
       }

  """
  @spec rpki(binary | integer, Keyword.t()) :: map
  def rpki(as, opts \\ []) do
    opts = Keyword.put(opts, :resource, as)
    dta = fetch("as-routing-consistency", opts)

    if dta.http == 200 do
      dta
      |> update_in(["prefixes"], fn map ->
        for {pfx, attrs} <- map, into: %{} do
          rpki = fetch("rpki-validation", resource: as, prefix: pfx)
          roas = Enum.filter(rpki["validating_roas"], fn roa -> roa["validity"] == "valid" end)
          pki_attrs = %{"rpki" => rpki["rpki_status"], "roas" => roas}

          {pfx, Map.merge(attrs, pki_attrs)}
        end
      end)
    else
      dta
    end
    |> Map.put(:source, "Ripe.API.Stat.rpki")
  end
end
