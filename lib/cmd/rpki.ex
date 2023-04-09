defmodule Ripex.Cmd.Rpki do
  @moduledoc """
  Report on an AS's routing consistency and RPKI validity.

  """

  @doc """
  This is the hint for this command
  """
  def main(args) do
    IO.puts("#{__MODULE__} running report now; #{inspect(args)}")
  end
end
