defmodule Localize.Locale.LocaleCacheProtectedTest do
  @moduledoc """
  Security regression: the locale-validation cache used to be a
  `:public` ETS table that any process in the BEAM could write to or
  delete from. It is now `:protected`, owned by
  `Localize.Locale.Loader`. Writes go through the owner GenServer
  (cast, fire-and-forget so the hot path doesn't block).
  """

  use ExUnit.Case, async: true

  describe "locale cache trust model" do
    test "the table is :protected, not :public" do
      assert :protected == :ets.info(:localize_locale_cache, :protection)
    end

    test "non-owner processes cannot write directly" do
      assert_raise ArgumentError, fn ->
        :ets.insert(:localize_locale_cache, {:cannot_write_directly, :nope})
      end
    end

    test "non-owner processes can read directly (read-side stays unblocked)" do
      # The invariant this test asserts is that a `:protected` table
      # still permits direct reads from a non-owner process. Cache
      # contents are immaterial — `:ets.tab2list/1` raising would
      # indicate the protection setting blocks reads, which it should
      # not. Avoid coupling to GenServer state by not depending on a
      # specific write having landed.
      assert is_list(:ets.tab2list(:localize_locale_cache))
    end
  end
end
