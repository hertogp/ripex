defmodule Ripe.API.Crt do
  @moduledoc """
  Functions to retrieve information from the [crt.sh](https://crt.sh).

  - https://crt.sh?q=<name>&output=json
  - https://crt.sh?id=<number>  <- won't work, only in browser?

  ## Examples
  - https://crt.sh/?Identity=example.nl&exclude=expired&deduplicate=Y
  """

  alias Ripe.API

  @base_url "https://crt.sh"
  @timeout 300_000

  # Helpers

  defp decode(%{http: 200, source: "Ripe.API.Crt.fetch"} = result),
    do: result

  defp decode(%{http: -1} = result),
    do: result

  # catch all: simply return the result without any decoding
  defp decode(result) do
    if result.http == 200 do
      result
    else
      # probably an error
      reason =
        Map.get(result, "messages", %{error: "no info"})
        |> Map.values()
        |> Enum.join("\n")

      result
      |> Map.put(:error, reason)
    end
  end

  defp url(query) do
    case String.match?(query, ~r/^\d+$/) do
      # TODO: for some reason id=<nr> fails?
      true -> "#{@base_url}/?id=#{query}&output=html"
      _ -> "#{@base_url}/?q=#{query}&output=json"
    end
  end

  # API

  @doc """
  Todo

  """
  @spec fetch(binary, Keyword.t()) :: map
  def fetch(query, opts \\ []) do
    # use a hefty timeout since it may take a while...
    # time = Keyword.get(opts, :timeout, @timeout)
    # opts = [opts: [adapter: [recv_timeout: time]]]
    opts = Keyword.put(opts, :timeout, @timeout)
    # |> Keyword.put(:headers, [{"accept", "text/html"}])

    opts =
      if String.match?(query, ~r/^\d+$/),
        do: Keyword.put(opts, :headers, [{"accept", "text/html"}]),
        else: opts

    query
    |> url()
    |> API.fetch(opts)
    |> Map.put(:source, "Ripe.API.Crt.fetch")
    |> Map.put(:query, query)
    |> decode()
  end
end
