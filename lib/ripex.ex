defmodule Ripex do
  @moduledoc """
  Documentation for `Ripex`.

  API's
  - Ripe.Stat
    * Ripe.Stat.API.endpoint(s)

  - Ripe.DB
    + Ripe.DB.lookup
      * Ripe.DB.Lookup.endpoint(s)

    + Ripe.DB.search
      * Ripe.DB.Search.endpoint(s)

  lib/ripe                       - api.ex utilities for all API's + general documentation
  lib/ripe/api

  lib/ripe/api/stat                   - stat.ripe Tesla setup
  lib/ripe/api/stat/endpoint(s)       - calls to endpoints

  lib/ripe/api/dbsearch               - db.ripe Tesla setup
  lib/ripe/api/dbsearh/endpoints(s)   - calls to RIPEDB endpoints

  lib/ripe/api/dblookup               - db.ripe Tesla setup
  lib/ripe/api/dblookup/endpoints(s)  - calls to RIPEDB endpoints

  lib/ripe/api/rdap
  lib/ripe/api/rdap/endpoints(s)

  """

  @doc """
  Hello world.

  ## Examples

      iex> Ripex.hello()
      :world

  """
  def hello do
    :world
  end
end
