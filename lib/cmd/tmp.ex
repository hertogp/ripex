defmodule Ripex.Cmd.Tmp do
  alias Ripe.API
  # see https://github.com/paraxialio/taxon/blob/master/lib/taxon/fetcher.ex
  # Other cloud IP's
  # - [x] http://digitalocean.com/geo/google.csv
  # - [x] https://api.cloudflare.com/client/v4/ips
  # - [ ] https://d7uri8nf7uskq.cloudfront.net/tools/list-cloudfront-ips (CloudFront)
  # - [x] https://docs.cloud.oracle.com/en-us/iaas/tools/public_ip_ranges.json
  # - [x] https://ip-ranges.amazonaws.com/ip-ranges.json
  # - [x] https://www.gstatic.com/ipranges/cloud.json (Google)
  # - [x] https://www.microsoft.com/en-us/download/confirmation.aspx?id=56519
  # - [ ] https://geoip.linode.com/
  # - [ ] use empty list (byte size 2) instead of 0 (byte size 3)
  # - [ ] https://support.google.com/a/answer/10026322?hl=en
  #       [ ] https://www.gstatic.com/ipranges/goog.json
  #       [x] https://www.gstatic.com/ipranges/cloud.json
  def main(_) do
    IO.puts("here we go!")

    providers = %{
      atlassian: "https://ip-ranges.atlassian.com/",
      aws: "https://ip-ranges.amazonaws.com/ip-ranges.json",
      azure: "https://www.microsoft.com/en-us/download/confirmation.aspx?id=56519",
      cloudflare: "https://api.cloudflare.com/client/v4/ips",
      google: "https://www.gstatic.com/ipranges/cloud.json",
      ocean: "http://digitalocean.com/geo/google.csv",
      oracle: "https://docs.cloud.oracle.com/en-us/iaas/tools/public_ip_ranges.json"
    }

    # [[ AWS ]]
    aws =
      Req.new(url: providers.aws)
      |> Ripe.API.call()
      |> API.move_keyup("ipv6_prefixes")
      |> API.move_keyup("prefixes")

    aws_v4 =
      aws["prefixes"]
      |> Enum.map(fn m -> m["ip_prefix"] end)

    aws_v6 =
      aws["ipv6_prefixes"]
      |> Enum.map(fn m -> m["ipv6_prefix"] end)

    # [[ Azure ]]
    body =
      Req.new(url: providers.azure)
      |> Ripe.API.call()
      |> Map.get(:body)

    url =
      Regex.run(~r"url=https://.*.json", body)
      |> hd()
      |> String.replace("url=", "")

    az_pfxs =
      Req.new(url: url)
      |> Ripe.API.call()
      |> Map.get(:body)
      |> Map.get("values")
      |> Enum.map(fn m -> m["properties"]["addressPrefixes"] end)
      |> List.flatten()

    # [[ Cloudflare ]]
    cflare =
      Req.new(url: providers.cloudflare)
      |> Ripe.API.call()
      |> get_in([:body, "result"])
      |> then(fn m -> m["ipv4_cidrs"] ++ m["ipv6_cidrs"] end)

    # [[ Google ]]
    google =
      Req.new(url: providers.google)
      |> Ripe.API.call()
      |> get_in([:body, "prefixes"])
      |> Enum.map(fn m -> Map.get(m, "ipv4Prefix", m["ipv6Prefix"]) end)

    # [[ Oracle ]]
    oracle =
      Req.new(url: providers.oracle)
      |> Ripe.API.call()
      |> get_in([:body, "regions"])
      |> Enum.map(fn m -> Map.get(m, "cidrs", []) |> Enum.map(fn m -> m["cidr"] end) end)
      |> List.flatten()
      |> Enum.filter(fn pfx -> pfx != "" end)

    # [[ Digital Ocean ]]
    ocean =
      Req.new(url: providers.ocean)
      |> Ripe.API.call()
      |> Map.get(:body)
      |> String.split("\n")
      |> Enum.map(fn line -> String.split(line, ",") |> hd() end)
      |> Enum.filter(fn pfx -> pfx != "" end)

    atlassian =
      Req.new(url: providers.atlassian)
      |> Ripe.API.call()
      |> get_in([:body, "items"])
      |> Enum.map(fn m -> m["cidr"] end)

    IO.inspect(length(aws_v4), label: :aws_v4_pfxs)
    IO.inspect(length(aws_v6), label: :aws_v6_pfxs)
    IO.inspect(length(az_pfxs), label: :azure_pfxs)
    IO.inspect(length(cflare), label: :cloudflare)
    IO.inspect(length(google), label: :google)
    IO.inspect(length(oracle), label: :oracle)
    IO.inspect(length(ocean), label: :ocean)
    IO.inspect(length(atlassian), label: :atlassian)

    prefixes = aws_v4 ++ aws_v6 ++ az_pfxs ++ cflare ++ google ++ oracle ++ ocean ++ atlassian

    # Build and minimize the trie
    max =
      prefixes
      |> Enum.map(fn p -> {p, 0} end)
      |> Iptrie.new()

    min =
      max
      |> Iptrie.minimize()

    Iptrie.count(max)
    |> IO.inspect(label: :max_total_pfxs)

    max
    |> :erlang.term_to_binary()
    |> :erlang.byte_size()
    |> then(fn size -> IO.inspect(size / 1_000_000, label: :max_size_MB) end)

    max
    |> :erlang.term_to_binary()
    |> then(fn t -> File.write!("tmp/max.ets", t) end)

    Iptrie.count(min)
    |> IO.inspect(label: :min_total_pfxs)

    min
    |> :erlang.term_to_binary()
    |> :erlang.byte_size()
    |> then(fn size -> IO.inspect(size / 1_000_000, label: :min_size_MB) end)

    min
    |> :erlang.term_to_binary()
    |> then(fn t -> File.write!("tmp/min.ets", t) end)

    # test all prefixes are found are in minimized trie
    IO.puts("\nLooking up all prefixes collected in minimized trie")
    IO.inspect(length(prefixes), label: :num_pfx_collected)
    IO.inspect(Iptrie.count(min), label: :minimized_pfx_count)

    prefixes
    |> Enum.reduce(0, fn pfx, acc -> if Iptrie.lookup(min, pfx), do: acc + 1, else: acc end)
    |> IO.inspect(label: :min_saw_N_pfxs)

    Iptrie.lookup(min, "20.31.37.66")
    |> IO.inspect(label: :some_ip)

    Iptrie.lookup(min, "52.160.0.0")
    |> IO.inspect(label: :azure_as_ip)

    Iptrie.lookup(min, "3.101.158.0")
    |> IO.inspect(label: :cloudfront)
  end
end
