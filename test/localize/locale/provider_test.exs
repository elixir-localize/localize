defmodule Localize.Locale.ProviderTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Localize.Locale.Provider

  describe "load_with_fallback/2 — parent-chain walking" do
    # Regression test for infinite recursion reported against v0.15.0.
    #
    # When a consumer's provider could not load the requested locale
    # AND could not load the parent-chain's resolved locale, the
    # walker called `Localize.Locale.parent/1` which returned the root
    # `und` tag. `Localize.Locale.to_locale_id/1` then routed the
    # tag's `nil` cldr_locale_id through `validate_locale/1` and
    # likely-subtag resolution, which could map `und` back to the
    # originally-requested locale (or to `:aa` etc. in other
    # environments). The walker then received the same locale_id it
    # had just tried, and looped forever emitting:
    #
    #   Attempting to load locale :ja (parent locale of :ja).
    #   Unable to load locale :ja and …
    #
    # Two guards now prevent this:
    #
    #   1. `Localize.Locale.to_locale_id/1` maps a bare `und` tag
    #      directly to `:und` without going through likely-subtag
    #      resolution.
    #
    #   2. `walk_parent_chain/4` carries a `visited` list and aborts
    #      to the `:en` fallback if it ever revisits a locale_id or
    #      the parent resolves to the current locale_id.

    defmodule AlwaysFailProvider do
      @moduledoc false
      @behaviour Provider
      def load(_), do: {:error, :missing}
      def available?(_), do: false
      def available_locales, do: []
      def get(_, _, _), do: nil
      def loaded?(_), do: false
      def store(_, _), do: :ok
    end

    test "terminates when every locale load fails (no infinite recursion)" do
      capture_log(fn ->
        task =
          Task.async(fn ->
            Provider.load_with_fallback(AlwaysFailProvider, :ja)
          end)

        case Task.yield(task, 2_000) || Task.shutdown(task) do
          {:ok, {:error, _}} ->
            :ok

          {:ok, unexpected} ->
            flunk("unexpected result: #{inspect(unexpected)}")

          nil ->
            flunk(
              "load_with_fallback/2 did not terminate within 2 seconds — " <>
                "parent-chain walker is looping. See provider.ex/walk_parent_chain/4."
            )
        end
      end)
    end

    test "terminates for :de when every locale load fails" do
      # Second locale to make sure the guard isn't specific to `:ja`.
      capture_log(fn ->
        task =
          Task.async(fn ->
            Provider.load_with_fallback(AlwaysFailProvider, :de)
          end)

        case Task.yield(task, 2_000) || Task.shutdown(task) do
          {:ok, {:error, _}} -> :ok
          nil -> flunk("load_with_fallback/2 looped for :de")
        end
      end)
    end
  end
end
