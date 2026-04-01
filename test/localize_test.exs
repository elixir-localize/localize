defmodule LocalizeTest do
  # async: false because doctests for with_locale/2 and get_locale/0
  # depend on global state (supported locales, default locale) that
  # can be mutated by concurrent tests.
  use ExUnit.Case, async: false
  doctest Localize
end
