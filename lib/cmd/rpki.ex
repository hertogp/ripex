defmodule Ripex.Cmd.Rpki do
  @moduledoc """
  Report on an AS's routing consistency and RPKI validity.

      Usage:

        ripex rpki [options] targets

        options include:
          -t  timeout, specify timeout in milliseconds (default 10000)
          -v  verbose, also report on the import/export peers

        targets can be:
          - an AS number, in which case the report covers the ASN only
          - an IP address, in which case the report includes all ASN's that advertise a corresponding routes
          - a domain name, in which case the report includes:
              - the AS the IP address of given domain name belongs to
              - check on the domain's name servers
              - check on the domain's mail relays (if any)

  TODO:
  - [ ] transform args to AS numbers from IP, AS<N>, N, prefix or fqdn.
  - [x] Use simple table, converts to table in pdf, looks gooed in markdown
  - [x] add stats to tables
  - [x] implement the options
  - [x] bail on bad options
  - [x] sort the import/export lists
  - [x] handle errors, timeouts etc... (try 6695)
  - [x] figure out why 6695 works in browser, not in escript (even with 60K ms timeout?)
  - [x] figure out why tesla does not seem to wait for specified timeout duration
  """

  @aliases [
    t: :timeout,
    v: :verbose
  ]
  @options [
    timeout: :integer,
    verbose: :boolean
  ]

  @doc """
  The rpki command main entry point.

  Invoked by `ripex rpki ...`
  """
  def main(argv) do
    {opts, args, bad} = OptionParser.parse(argv, strict: @options, aliases: @aliases)

    if length(bad) > 0 do
      Enum.each(bad, fn x -> IO.puts("Option #{inspect(x)} is not supported") end)
      IO.puts("Please see usage below.\n\n")
      IO.puts(@moduledoc)
      System.halt(1)
    end

    [meta(), Enum.map(args, fn as -> report(as, opts) end)]
    |> IO.puts()
  end

  # [[ Helpers ]]

  def label(args) do
    args
    |> Enum.map(&do_label/1)
    |> Enum.map(&do_value/1)
    |> List.flatten()
    |> Enum.uniq_by(fn m -> m.as end)
  end

  defp do_label(arg) do
    cond do
      String.match?(arg, ~r/^\d+$/) -> %{type: :as, as: arg}
      String.match?(arg, ~r/^as\d+$/i) -> %{type: :as, as: String.replace(arg, ~r/as/i, "")}
      :ok == Pfx.parse(arg) |> elem(0) -> %{type: :pfx, pfx: arg}
      true -> %{type: :domain, domain: arg}
    end
  end

  defp do_value(%{type: :pfx} = arg) do
    Ripe.API.Stat.ip2asns(arg.pfx)
    |> Enum.map(fn as -> Map.put(arg, :as, as) end)
  end

  defp do_value(%{type: :domain} = arg) do
    ips =
      arg.domain
      |> String.to_charlist()
      |> :inet_res.lookup(:in, :a)
      |> Enum.map(fn ip -> Map.put(arg, :ip, "#{Pfx.new(ip)}") end)

    for m <- ips do
      Ripe.API.Stat.ip2asns(m.ip)
      |> Enum.map(fn as -> Map.put(m, :as, as) end)
    end
  end

  defp do_value(arg),
    do: arg

  defp aligned(lol) do
    # given a list of lists of strings, calculate column widths and pad cell
    # values with an appropiate amount of spaces.  Ensure each line ends with
    # a newline.
    widths =
      for elems <- lol do
        elems
        |> Enum.with_index(fn str, idx -> {idx, String.length(str)} end)
        |> Map.new()
      end
      |> Enum.reduce(%{}, fn m, a -> Map.merge(a, m, fn _k, v1, v2 -> max(v1, v2) end) end)

    lol
    |> Enum.map(fn words ->
      Enum.with_index(words, fn elm, idx ->
        w = 1 + max(Map.get(widths, idx, 0), String.length(elm))
        String.pad_trailing(elm, w, " ")
      end)
      |> then(fn words -> [words, "\n"] end)
    end)
  end

  defp head(obj) do
    ["# AS#{obj["asn"]}\n\n"]
  end

  defp meta(),
    do: [
      "---\n",
      "title: RPKI check\n",
      "author: ripex\n",
      "date: #{Date.utc_today()}\n",
      "...\n\n"
    ]

  defp peers(obj, type) when type in ["imports", "exports"] do
    lol =
      obj
      |> Map.get(type)
      |> Enum.reduce([], fn m, acc ->
        [["#{m["peer"]}", "#{m["in_bgp"]}", "#{m["in_whois"]}"] | acc]
      end)
      |> Enum.sort()

    lol =
      [["peer", "bgp", "whois"] | lol]
      |> aligned()

    stats =
      obj
      |> Map.get(type, [])
      |> Enum.frequencies_by(fn m -> ["#{m["in_bgp"]}", "#{m["in_whois"]}"] end)
      |> Enum.reduce([], fn {set, count}, acc -> [["#{count}" | set] | acc] end)
      |> then(fn lol -> [["count", "bgp", "whois"] | lol] end)
      |> aligned()

    case length(lol) do
      1 ->
        ["\n## AS#{obj["asn"]} #{type}\n\nNo peers found.\n\n"]

      _ ->
        [
          "\n## AS#{obj["asn"]} #{type}\n\n",
          table(lol),
          "\nTable: peer #{type}.\n\n\n",
          table(stats),
          "\nTable: #{type} stats.\n\n\n"
        ]
    end
  end

  defp report(as, opts) do
    timeout = Keyword.get(opts, :timeout, 10000)
    verbose = Keyword.get(opts, :verbose, false)
    IO.inspect(timeout, label: :timeout)

    with %{http: 200} = obj <- Ripe.API.Stat.rpki(as, timeout: timeout) do
      case verbose do
        false -> [head(obj), routes(obj)]
        true -> [head(obj), routes(obj), peers(obj, "imports"), peers(obj, "exports")]
      end
    else
      %{error: :timeout} = err ->
        [
          "# AS#{as}\n\n",
          "Error: #{err[:error]}, maybe try -t N where N > 10000?\n",
          "Url: #{err[:url]}\n\n"
        ]

      err ->
        [
          "# AS#{as}\n\n",
          "Error: #{err[:error]}\n",
          "http: #{err[:http]}\n",
          "Url: #{err[:url]}\n\n"
        ]
    end
  end

  defp roas(roas) do
    # return soa summary as 1 string
    # - when not valid, there seem to be no roa's in the list?

    # for roa <- roas, roa["validity"] == "valid", into: [] do
    #   "#{roa["prefix"]}-#{roa["max_length"]}-#{roa["origin"]}"
    # end
    # |> Enum.join(" ")

    for roa <- roas, into: [] do
      "#{roa["prefix"]}-#{roa["max_length"]}-#{roa["origin"]}"
    end
    |> Enum.join(" ")
  end

  defp routes(obj) do
    lol =
      for {p, v} <- obj["prefixes"], into: [] do
        [p, "#{v["in_bgp"]}", "#{v["in_whois"]}", v["rpki"], roas(v["roas"])]
      end
      |> Enum.sort()

    lol =
      [["prefix", "bgp", "whois", "rpki", "roas"] | lol]
      |> aligned()

    stats =
      Map.get(obj, "prefixes", %{})
      |> Enum.frequencies_by(fn {_pfx, m} -> ["#{m["in_bgp"]}", "#{m["in_whois"]}", m["rpki"]] end)
      |> Enum.reduce([], fn {set, count}, acc -> [["#{count}" | set] | acc] end)
      |> then(fn lol -> [["count", "bgp", "whois", "rpki"] | lol] end)
      |> aligned()

    [
      "## AS#{obj["asn"]} prefixes\n\n",
      table(lol),
      "\nTable: as routing consistency\n\n\n",
      table(stats),
      "\nTable: consistency stats.\n\n\n"
    ]
  end

  defp table([head | tail]) do
    seps =
      head
      |> hd()
      |> Enum.map(fn w -> String.length(w) - 1 end)
      |> Enum.map(fn l -> String.duplicate("-", l) end)
      |> Enum.join(" ")

    [head, seps, "\n", tail]
  end
end
