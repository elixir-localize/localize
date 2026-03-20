defmodule Localize.Collation.FastLatinTest do
  use ExUnit.Case

  setup_all do
    Localize.Collation.ensure_loaded()
    :ok
  end

  doctest Localize.Collation.FastLatin
end
