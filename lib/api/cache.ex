defmodule Ripe.API.Cache do
  @moduledoc """
  A simple cache using url's as keys to cache associated data
  """

  @options [:set, :public, :named_table]
  @cache __MODULE__

  @doc """
  Create the #{__MODULE__} if it doesn't exist already.

  """
  @spec start() :: :ok | {:error, :already_started}
  def start() do
    true = :ets.new(@cache, @options)
    :ok
  rescue
    ArgumentError -> {:error, :already_started}
  end

  @doc """
  Returns the cached results for given `url` or nil

  """
  @spec get(binary) :: any
  def get(url) do
    case :ets.lookup(@cache, url) do
      [{^url, data}] -> data
      _other -> nil
    end
  rescue
    ArgumentError ->
      start()
      nil
  end

  @doc """
  Put given `data` under given `url` in the cache, returns the data.

  """
  @spec put(any, binary) :: any | :error
  def put(data, url) do
    true = :ets.insert(@cache, {url, data})
    data
  rescue
    ArgumentError ->
      :ets.new(@cache, @options)
      true = :ets.insert(@cache, {url, data})
      data
  end
end
