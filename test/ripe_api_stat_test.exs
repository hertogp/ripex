defmodule Ripe.API.StatTest do
  use ExUnit.Case, async: false
  doctest Ripe.API.Stat, import: true

  @filename "ripe-api-stat.ets"

  setup_all do
    Ripe.API.Cache.read(@filename)

    on_exit(fn ->
      Ripe.API.Cache.save(@filename)
    end)
  end
end
