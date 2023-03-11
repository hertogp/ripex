defmodule Ripe.API do
  @moduledoc """
  Utility functions to be used by all endpoints across all RIPE API's..

  """

  # Helpers
  # none yet

  # API

  @doc """
  Rename keys in `map` using `keymap`, recursively.

  This function will recurse on values that are either a map or list themselves.
  """
  @spec rename(map, map) :: map
  def rename(map, keymap) when is_map(map) do
    for {k, v} <- map, into: %{} do
      knew = Map.get(keymap, k, k)

      cond do
        is_map(v) -> {knew, rename(v, keymap)}
        is_list(v) -> {knew, Enum.map(v, fn elm -> rename(elm, keymap) end)}
        true -> {knew, v}
      end
    end
  end

  def rename(data, _keymap),
    do: data

  @doc """
  Reduce a `list` of similar maps to a map by `key`.

  Each map in the list is added to an accumulator map
  using `map[key]` as key while also dropping `map[key]`
  from the individual map.

  """
  @spec map_bykey(list, binary) :: map
  def map_bykey(list, key) when is_list(list) do
    for map <- list, Map.has_key?(map, key), into: %{} do
      {map[key], Map.delete(map, key)}
    end
  end

  # recursively remove keys
  @doc """
  Dop given `keys` from `map`, recursively.

  This function will recurse on values that are either a map or list themselves.

  """
  @spec remove(map, [binary]) :: map
  def remove(map, keys) when is_map(map) do
    for {k, v} <- Map.drop(map, keys), into: %{} do
      cond do
        is_map(v) -> {k, remove(v, keys)}
        is_list(v) -> {k, Enum.map(v, fn elm -> remove(elm, keys) end)}
        true -> {k, v}
      end
    end
  end

  # only remove keys from a map
  def remove(data, _keys),
    do: data
end
