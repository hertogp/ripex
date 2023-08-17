defmodule Ripex.Cmd.Crt do
  alias Ripe.API

  @moduledoc """

  Usage: ripex crt [options] name ...

  `name` can be:
  - a crt.sh id number
  - regular name
  - fully qualified domain name

  `options` include:
  `-r` recursive
  `-x N`, exclude certificates that expired N+ days ago.

  Searching for a regular name will match on certificate identities and the results
  do not include all SAN names apparently.  In such cases, if more detail is needed,
  the `-r` flag will also query crt.sh for each fqdn (common name) found. which
  will replace the entry for the fqdn.  Note that this may take a long time.

  TODO:
  - [ ] implement the -r flag
  - [ ] check other query parameters, e.g. via the advanced search (can't find documentation?)
  - [ ] do not report expired certificates if a new, valid one is seen

  """

  @aliases [
    c: :csv,
    t: :timeout,
    x: :exclude
  ]
  @options [
    csv: :boolean,
    exclude: :integer,
    timeout: :integer
  ]

  @csv_fields "tstamp,id,subject,idx,san,start,stop,expiry,C,ST,L,O,CN"

  @doc """
  The rpki command main entry point.

  Invoked by `ripex crt ...`
  """
  def main(argv) do
    {opts, args, bad} = OptionParser.parse(argv, strict: @options, aliases: @aliases)

    if length(bad) > 0 do
      Enum.each(bad, fn x -> IO.puts("Option #{inspect(x)} is not supported") end)
      IO.puts("Please see usage below.\n\n")
      IO.puts(@moduledoc)
      System.halt(1)
    end

    timeout = Keyword.get(opts, :timeout, 300_000)

    IO.puts(@csv_fields)

    for name <- args do
      API.Crt.fetch(name, timeout: timeout)
      |> Map.put(:opts, opts)
      |> decode()
    end
  end

  # [[ Helpers ]]

  defp decode(%{http: -1} = result),
    do: IO.inspect(result)

  defp decode(%{http: 200} = result) do
    min_age = result.opts |> Keyword.get(:exclude, -31)

    data = Map.get(result, :body, "no data in response")

    cond do
      is_binary(data) -> Map.put(result, :error, data)
      is_list(data) -> decode_entries(data, min_age)
      true -> %{error: inspect(data)}
    end

    # result
    # |> Map.get(:body, [])
    # |> decode_entry(min_age)
  end

  defp decode(result) do
    %{
      http: -1,
      error: inspect(result, limit: 10)
    }
  end

  defp decode_entries([], _),
    do: IO.puts("")

  defp decode_entries([map | tail], min_age) do
    expiry = expiry(map["not_after"])

    unless expiry < min_age do
      line = [
        map["entry_timestamp"],
        ",",
        "#{map["id"]}",
        ",",
        map["common_name"],
        ",",
        "0",
        ",",
        "n/a",
        ",",
        map["not_before"],
        ",",
        map["not_after"],
        ",",
        "#{expiry}",
        ",",
        map["issuer_name"] |> decode_issuer()
      ]

      alts = san_names("#{map["id"]}")

      case alts do
        [] ->
          IO.puts(line)

        names ->
          for {name, idx} <- names do
            line
            |> List.replace_at(6, "#{idx}")
            |> List.replace_at(8, "#{name}")
            |> IO.puts()
          end
      end
    end

    decode_entries(tail, min_age)
  end

  def decode_issuer(issuer) do
    # "O=VeriSign Trust Network, OU=\"VeriSign, Inc.\", OU=VeriSign International Server CA - Class 3, OU=www.verisign.com/CPS Incorp.by Ref. LIABILITY LTD.(c)97 VeriSign"
    # `-> so replace ',' inside qoutes with ';'

    map =
      issuer
      |> String.replace(~r/"([^,]+),([^,]+)"/, "\\1;\\2")
      |> String.split(~r/,\s*/, trim: true)
      |> Enum.map(fn str -> String.split(str, "=") end)
      |> Enum.map(fn [h, t] -> {String.upcase(h), t} end)
      |> Map.new()

    [
      Map.get(map, "O", "n/a"),
      ",",
      Map.get(map, "C", "n/a"),
      ",",
      Map.get(map, "ST", "n/a"),
      ",",
      Map.get(map, "L", "n/a"),
      ",",
      Map.get(map, "CN", "n/a")
    ]
  end

  defp expiry(date) do
    date =
      "#{date}Z"
      |> String.replace("ZZ", "Z")

    last =
      case DateTime.from_iso8601(date) do
        {:ok, datetime, _} -> datetime
        _ -> nil
      end

    now =
      case DateTime.now("Etc/UTC") do
        {:ok, datetime} -> datetime
      end

    case {last, now} do
      {nil, _} -> "error"
      {last, now} -> DateTime.diff(last, now, :day)
    end
  end

  def san_names(id) do
    id
    |> API.Crt.fetch()
    |> Map.get(:body)
    |> then(fn str -> Regex.scan(~r/dns:[a-zA-Z0-9._-]+/i, str) end)
    |> List.flatten()
    |> Enum.map(fn s ->
      String.split(s, ":")
      |> Enum.at(-1)
    end)
    |> Enum.with_index()
  end
end
