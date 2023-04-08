defmodule Ripe.API.CacheTest do
  use ExUnit.Case, async: false
  doctest Ripe.API.Cache, import: true

  @filename "ripe-api-cache.ets"

  setup_all do
    IO.inspect(Ripe.API.Cache.read(@filename))

    on_exit(fn ->
      Ripe.API.Cache.save(@filename)
    end)
  end
end
