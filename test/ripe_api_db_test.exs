defmodule Ripe.API.DBTest do
  use ExUnit.Case, async: false
  doctest Ripe.API.DB, import: true

  @filename "ripe-api-db.ets"

  setup_all do
    Ripe.API.Cache.read(@filename)

    on_exit(fn ->
      Ripe.API.Cache.save(@filename)
    end)
  end
end
