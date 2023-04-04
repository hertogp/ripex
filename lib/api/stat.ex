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
  managable datastructure.  These include:

  - [announced-prefixes](https://stat.ripe.net/docs/02.data-api/announced-prefixes.html)
  - [network-info](https://stat.ripe.net/docs/02.data-api/network-info.html)
  - [abuse-contact-finder](https://stat.ripe.net/docs/02.data-api/abuse-contact-finder.html)
  - [as-overview](https://stat.ripe.net/docs/02.data-api/as-overview.html)
  - [as-routing-consistency](https://stat.ripe.net/docs/02.data-api/as-routing-consistency.html)
  - [prefix-overview](https://stat.ripe.net/docs/02.data-api/prefix-overview.html)
  - [rpki-validation](https://stat.ripe.net/docs/02.data-api/rpki-validation.html)

  Other endpoints will simply yield the json decoded results.

  Other functions are basically convenience functions that combine the results
  of two or more endpoints, like `rpki/2`.


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

  `params` is a `t:Keyword.t/0` list and depends on the endpoint being accessed.

  Note that this list may include a `Ripe.API.Stat`-specific `timeout: N`
  option to wait N milliseconds instead of the default 2000 ms.  This is
  dropped from params, which then should list the parameters and their values
  to use for given `endpoint`.

  In case of success, the result is a map with atom keys that include:
  - `http:` - the http return code
  - `method`: - always `:get`
  - `opts` - options passed on to the http client
  - `source` - "Ripe.API.Stat." <> endpoint

  and binary keys that come from the data returned by the API endpoint,
  which will be different across the endpoints.

  ## [abuse-contact-finder](https://stat.ripe.net/docs/02.data-api/abuse-contact-finder.html)

  The abuse contract finder takes a single `resource` parameter whose value can
  be an IP address, prefix or an AS number.

      iex> fetch("abuse-contact-finder", resource: "94.198.159.35")
      ...> |> Map.put("version", "2.1")
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


  ## [announced-prefixes](https://stat.ripe.net/docs/02.data-api/announced-prefixes.html)

  ## [as-overview](https://stat.ripe.net/docs/02.data-api/as-overview.html)

  ## [as-routing-consistency](https://stat.ripe.net/docs/02.data-api/as-routing-consistency.html)

  ## [network-info](https://stat.ripe.net/docs/02.data-api/network-info.html)

  ## [prefix-overview](https://stat.ripe.net/docs/02.data-api/prefix-overview.html)

  ## [rpki-validation](https://stat.ripe.net/docs/02.data-api/rpki-validation.html)

  """
  @spec fetch(binary, Keyword.t()) :: map
  def fetch(endpoint, params \\ []) do
    {time, params} = Keyword.pop(params, :timeout, 2000)
    timeout = [opts: [recv_timeout: time]]
    first_word = fn str -> String.split(str) |> hd() end

    endpoint
    |> url(params)
    |> API.fetch(timeout)
    |> IO.inspect()
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
  Returns a map with information on the routes announced by given `asnr`.

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
