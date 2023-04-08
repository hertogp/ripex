defmodule Ripe.APITest do
  use ExUnit.Case, async: false
  doctest Ripe.API, import: true

  @filename "ripe-api.ets"

  setup_all do
    Ripe.API.Cache.read(@filename)

    on_exit(fn ->
      Ripe.API.Cache.save(@filename)
    end)
  end
end
