defmodule Ripe.API.Cache do
  @moduledoc """
  A simple cache using url's as keys to cache associated data.
  """

  @options [:set, :public, :named_table]
  @cache __MODULE__

  @doc """
  Clears the cache.

  """
  @spec clear() :: :ok
  def clear() do
    true = :ets.delete_all_objects(@cache)
    :ok
  end

  @doc """
  Delete an entry under given `url` from the cache.

  Returns `:ok`, even if the entry does not exist.

  ## Examples

      iex> del("missing")
      :ok

      iex> del("https://discography?query=acdc&year=1975&month=dec")
      :ok
      #
      iex> ["acdc", "T.N.T", 1975]
      ...> |> put("https://discography?query=acdc&year=1975&month=dec")
      ["acdc", "T.N.T", 1975]

  """
  @spec del(binary) :: :ok
  def del(url) do
    true = :ets.delete(@cache, url)
    :ok
  end

  @doc """
  Returns the cached result for given `url` or nil

  ## Examples

      iex> get("missing")
      nil

      iex> get("https://discography?query=acdc&year=1975&month=dec")
      ["acdc", "T.N.T", 1975]

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

  ## Example

      iex> ["acdc", "High Voltage", 1975]
      ...> |> put("https://discography?query=acdc&year=1975&month=feb")
      ["acdc", "High Voltage", 1975]
      #
      iex> get("https://discography?query=acdc&year=1975&month=feb")
      ["acdc", "High Voltage", 1975]



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

  Given `filename` is looked for in the private directory, so do not
  use a filepath.

  ## Example

      iex> read("missing")
      :error

      iex> read("ripe-api-cache.ets")
      :ok

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
