defmodule Ripex.Cmd do
  def available?(cmd) do
    cmd
    |> module()
    |> Code.ensure_loaded!()
    |> function_exported?(:main, 1)
  end

  @doc """
  Returns a command module's @moduledoc string or an error string.
  """
  def doc(cmd) do
    case Code.fetch_docs(module(cmd)) do
      {_, _, _, _, %{"en" => doc}, _, _} -> doc
      _ -> "#{cmd} not available"
    end
  end

  def dispatch(cmd, fun, args) do
    cmd
    |> module()
    |> apply(fun, args)
  end

  def hint(cmd) do
    cmd
    |> doc()
    |> String.split("\n", trim: true)
    |> Enum.at(0)
  end

  @doc """
  Returns a list of available commands under the `Ripex.Cmd` namespace.

  """
  @spec list() :: [binary]
  def list() do
    with {:ok, list} <- :application.get_key(:ripex, :modules) do
      list
      |> Enum.map(fn m -> Module.split(m) end)
      |> Enum.filter(fn names -> "Cmd" in names and length(names) > 2 end)
      |> Enum.map(fn names -> List.last(names) |> String.downcase() end)
    else
      _ -> []
    end
  end

  @spec module(binary) :: atom
  def module(cmd),
    do: Module.concat(__MODULE__, String.capitalize(cmd))
end
