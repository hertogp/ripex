defmodule Ripe.API.Crt do
  @moduledoc """
  Functions to retrieve information from the [crt.sh](https://crt.sh).

  - https://crt.sh?q=<name>&output=json
  - https://crt.sh?id=<number>  <- won't work, only in browser?

  ## Examples
  - https://crt.sh/?Identity=example.nl&exclude=expired&deduplicate=Y
  """

  alias Ripe.API

  # Helpers

  defp decode(%{http: 200, source: "Ripe.API.Crt.call"} = result),
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

  # API

  @base_req Req.new(
              base_url: "https://crt.sh",
              json: true,
              headers: [accept: "text/html", user_agent: "ripex"],
              receive_timeout: 60_000
            )

  # Note: query for id is done by Ripex.Cmd.Crt for san names
  defp params(query) do
    case String.match?(query, ~r/^\d+$/) do
      # TODO: for some reason id=<nr> fails?
      true -> [id: "#{query}", output: "html"]
      _ -> [q: "#{query}", output: "json"]
    end
  end

  @doc """
  [ ] ToDo
  """
  @spec call(binary, Keyword.t()) :: map
  def call(query, opts \\ []) do
    @base_req
    |> Req.merge(params: params(query))
    |> Req.merge(opts)
    |> API.call()
    |> Map.put(:source, "Ripe.API.Crt.call")
    |> Map.put(:query, query)
    |> decode()
  end
end
