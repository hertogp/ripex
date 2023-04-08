defmodule Ripe.API.Cache do
  @moduledoc """
  A simple ets-based cache using url's as keys to cache associated data.

  The process that initially `start/0`'s the cache, owns the corresponding ets
  table.  When that process dies, the table is destroyed.

  The `read/1` and `save/1` functions were implemented mainly to allow for
  having a cache with known content during unit tests.

  Entries are cached as `{url, data, timestamp}` where timestamp has the
  `:second` timeunit.  Use `get/1` if you do not care about the age of the
  cached entry and `get/2` otherwise.


  """

  @options [:set, :public, :named_table]
  @cache __MODULE__

  # [[ Helpers ]]

  defp timestamp(),
    do: System.monotonic_time(:second)

  @doc """
  Clears the cache.

  ## Example

      iex> clear()
      :ok
      iex> :ets.info(Ripe.API.Cache)
      ...> |> Keyword.get(:size)
      0
      # restore cache for this test module
      iex> read("ripe-api-cache.ets")
      :ok
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

      iex> read("ripe-api-cache.ets")
      iex> get("https://discography?query=acdc&title=TNT")
      ["acdc", "TNT", 1975]
      iex> del("https://discography?query=acdc&title=TNT")
      :ok
      iex> get("https://discography?query=acdc&title=TNT")
      nil

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

      iex> read("ripe-api-cache.ets")
      iex> get("https://discography?query=acdc&title=TNT")
      ["acdc", "TNT", 1975]

  """
  @spec get(binary) :: any
  def get(url) do
    case :ets.lookup(@cache, url) do
      [{^url, data, _tstamp}] ->
        data

      _other ->
        nil
    end
  rescue
    ArgumentError ->
      start()
      nil
  end

  @doc """
  Returns the cached result for given `url` or nil if the entry is older than
  given `ttl` in seconds.

  `nil` is also returned if there is no such entry. And the ttl is measured in seconds.

  ## Example

      iex> read("ripe-api-cache.ets")
      iex> get("https://discography?query=acdc&title=TNT", 10)
      ["acdc", "TNT", 1975]
      iex> get("https://discography?query=acdc&title=TNT", -1)
      nil

  """
  @spec get(binary, integer) :: any
  def get(url, ttl) do
    case :ets.lookup(@cache, url) do
      [{^url, data, tstamp}] ->
        if timestamp() - tstamp > ttl,
          do: nil,
          else: data

      _other ->
        nil
    end
  rescue
    ArgumentError ->
      start()
      nil
  end

  @doc """
  Put given `data` under given `url` in the cache, returns the data.

  The entry is stored as `{url, data, timestamp}`, where `timestamp` is the
  current monotonic time in seconds.

  ## Example

      iex> ["acdc", "High Voltage", 1975]
      ...> |> put("https://discography?query=acdc&title=HighVoltage")
      ["acdc", "High Voltage", 1975]
      #
      iex> get("https://discography?query=acdc&title=HighVoltage")
      ["acdc", "High Voltage", 1975]



  """
  @spec put(any, binary) :: any | :error
  def put(data, url) do
    true = :ets.insert(@cache, {url, data, timestamp()})
    data
  rescue
    ArgumentError ->
      :ets.new(@cache, @options)
      true = :ets.insert(@cache, {url, data})
      data
  end

  @doc """
  Clears the cache, then tries to load entries from given `filename`.

  Given `filename` is looked for in the private directory, so do not
  use a filepath.  If the file does not exist an `:error` is returned
  and the cache will have been cleared.

  Note that any entries created will have the timestamp of the moment
  of creating the entries, i.e. their timestamps are refreshed.

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

      for {url, data, _timestamp} <- entries,
          do: put(data, url)

      :ok
    else
      :error
    end
  end

  @doc """
  Saves the cache to a file with `filename` in `:ripex`'s private directory.

  The cache's ets table is first converted to a list and that list is saved
  as an erlang binary term.

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
