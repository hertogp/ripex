defmodule Ripex.CLI do
  @moduledoc false

  def main(args \\ System.argv()) do
    case shortcut(args) do
      :help -> usage()
      :version -> IO.puts("ripex - #{version()}")
      nil -> proceed(args)
    end
  end

  # [[ Helpers ]]

  defp proceed([]),
    do: usage()

  defp proceed(["help"]) do
    cmds = Ripex.Cmd.list()
    IO.puts("ripex - #{version()}\n")
    IO.puts("available commands:\n")

    for cmd <- cmds,
        do: IO.puts("#{cmd} - and does this")
  end

  defp proceed(["help" | args]),
    do: IO.puts("help for #{inspect(args)}")

  defp proceed([cmd | args]) do
    IO.puts("cmd #{cmd}, args #{inspect(args)}")
  end

  @spec shortcut([binary]) :: :help | :version | nil
  defp shortcut([]),
    do: :help

  defp shortcut([arg | _rest]) do
    cond do
      arg in ["-h", "--help"] -> :help
      arg in ["-v", "--version"] -> :version
      true -> nil
    end
  end

  defp usage() do
    IO.puts("""

    Ripex is a tool to generate reports using RIPE NCC information.

    Usage: ripex CMD

      ripex - #{version()}

      ripex          - Lists the available CMD's
      ripex help CMD - Prints the help for a given command
    """)
  end

  @spec version() :: binary
  defp version() do
    Application.spec(:ripex)
    |> Keyword.get(:vsn)
    |> to_string()
  end
end
