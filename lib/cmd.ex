defmodule Ripex.Cmd do
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

  @spec module(binary) :: atom | {:error, any}
  def module(cmd) do
    module = Module.concat(__MODULE__, String.capitalize(cmd))

    case Code.ensure_loaded(module) do
      {:error, :nofile} ->
        {:error, "command not supported"}

      {:error, reason} ->
        {:error, reason}

      {:module, module} ->
        module
    end
  end
end
