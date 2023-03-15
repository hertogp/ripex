defmodule Ripe.API do
  @moduledoc """
  Utility functions to be used by all endpoints across all RIPE API's..

  """

  # API

  @spec get_at(map | list, [binary | number]) :: any
  def get_at(data, []),
    do: data

  def get_at(nil, _),
    do: nil

  def get_at(data, [key | tail]) when is_map(data) do
    data
    |> Map.get(key, nil)
    |> get_at(tail)
  end

  def get_at(data, [key | tail]) when is_list(data) do
    data
    |> List.pop_at(key)
    |> elem(0)
    |> get_at(tail)
  end

  @doc """
  Given a map, promote values that consist of a single given `key` => value.
  """
  @spec promote(map, binary) :: map
  def promote(map, key) when is_map(map) do
    promoted =
      for {k, v} <- map, is_map(v) and Map.has_key?(v, key), into: %{} do
        {k, Map.get(v, key)}
      end

    Map.merge(map, promoted)
  end

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

  The maps in the list should share a common key with
  values unique compared to the other maps in the list.

  Each map in the list is added to an accumulator map
  using the common key's value (`map[key]`) as the key
  in the accumulator map, while also dropping `map[key]`
  from the individual map and adding a `:idx` key,value
  pair that records its original position in the list.


  """
  @spec map_bykey(list | map, binary) :: map
  def map_bykey(list, key) when is_list(list) do
    for {map, idx} <- Enum.with_index(list), Map.has_key?(map, key), into: %{} do
      new_key = map[key]

      map =
        map
        |> Map.put(:idx, idx)
        |> Map.delete(key)

      {new_key, map}
      # {map[key], Map.delete(map, key)}
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
