defmodule Ripe.API.Cache do
  @moduledoc """
  A simple cache using url's as keys to cache associated data.
  """

  @options [:set, :public, :named_table]
  @cache __MODULE__

  @doc """
  Clears the cache.

  """
  @spec clear() :: true
  def clear(),
    do: :ets.delete_all_objects(@cache)

  @doc """
  Delete an entry from the cache.

  """
  @spec del(binary) :: :ok
  def del(url) do
    true = :ets.delete(@cache, url)
    :ok
  end

  @doc """
  Returns the cached result for given `url` or nil

  ## Example

      iex> get("missing")
      true
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

  @doc """
  Clears the cache and tries to load entries from given `filename`.

  Given `filename` is looked for in the private directory, so donot
  use a filepath.
  """
  @spec read(binary) :: :ok | :error
  def read(filename) do
    :ets.delete_all_objects(@cache)

    fpath = Path.join(:code.priv_dir(:ripex), filename)

    if File.exists?(fpath) do
      entries =
        fpath
        |> File.read!()
        |> :erlang.binary_to_term()

      for {k, v} <- entries, do: put(v, k)
      :ok
    else
      :error
    end
  end

  @doc """
  Saves the cache to a file with `filename`.

  """
  @spec save(binary) :: :ok | {:error, any}
  def save(filename) do
    # not using tab2file, since that also stores the table name.
    # we want to be able to load the cache without recreating it.
    fpath = Path.join(:code.priv_dir(:ripex), filename)

    :ets.tab2list(@cache)
    |> :erlang.term_to_binary()
    |> then(fn term -> File.write!(fpath, term) end)
  end

  @doc """
  Create the #{__MODULE__} if it doesn't exist already.

  """
  @spec start() :: {:ok, atom} | {:error, :already_started}
  def start() do
    {:ok, :ets.new(@cache, @options)}
  rescue
    ArgumentError -> {:error, :already_started}
  end
end
