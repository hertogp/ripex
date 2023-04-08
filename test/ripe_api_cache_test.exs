defmodule Ripe.API.CacheTest do
  use ExUnit.Case, async: false
  doctest Ripe.API.Cache, import: true

  @filename "ripe-api-cache.ets"

  setup_all do
    Ripe.API.Cache.read(@filename)

    # ensure some entries
    ["acdc", "T.N.T", 1975]
    |> Ripe.API.Cache.put("https://discography?query=acdc&year=1975&month=dec")

    on_exit(fn ->
      Ripe.API.Cache.save(@filename)
    end)
  end
end
