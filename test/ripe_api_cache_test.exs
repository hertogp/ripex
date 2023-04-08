defmodule Ripe.API.CacheTest do
  use ExUnit.Case, async: false
  doctest Ripe.API.Cache, import: true

  @filename "ripe-api-cache.ets"

  setup_all do
    Ripe.API.Cache.clear()

    # ensure some entries, donot save cache afterwards
    ["acdc", "TNT", 1975]
    |> Ripe.API.Cache.put("https://discography?query=acdc&title=TNT")

    ["acdc", "High Voltage", 1975]
    |> Ripe.API.Cache.put("https://discography?query=acdc&title=HighVoltage")

    Ripe.API.Cache.save(@filename)

    :ok
  end
end
