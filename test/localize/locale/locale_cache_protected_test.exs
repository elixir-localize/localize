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
      # Trigger a write through the public API.
      {:ok, _tag} = Localize.validate_locale("en-AU")
      # Sync with the owner so the cast has been processed.
      :sys.get_state(Localize.Locale.Loader)
      # Now read directly.
      assert [_ | _] = :ets.tab2list(:localize_locale_cache)
    end
  end
end
