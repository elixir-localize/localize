defmodule Localize.AtomSafeValidationTest do
  @moduledoc """
  Covers public validation paths that accept caller-provided strings.

  These tests assert that unknown inputs are rejected without interning
  new atoms. They do not cover language tag parsing or permissive locale
  best matching.
  """

  use ExUnit.Case, async: true

  describe "calendar, number system, and locale availability validation" do
    test "known string inputs still resolve" do
      assert Localize.available_locale_id?("en")
      assert {:ok, :persian} = Localize.validate_calendar("persian")
      assert {:ok, :islamic_umalqura} = Localize.validate_calendar("islamic-umalqura")
      assert {:ok, :ethiopic_amete_alem} = Localize.validate_calendar("ethioaa")
      assert {:ok, :latn} = Localize.validate_number_system("latn")
    end

    test "unknown strings do not become atoms" do
      suffix = System.unique_integer([:positive])
      unknown_calendar = "localize_atom_safe_calendar_#{suffix}"
      unknown_number_system = "localizeatomsafenumbersystem#{suffix}"
      unknown_locale = "localize-atom-safe-locale-#{suffix}"

      refute existing_atom?(unknown_calendar)
      refute existing_atom?(unknown_number_system)
      refute existing_atom?(unknown_locale)

      assert {:error, %Localize.UnknownCalendarError{}} =
               Localize.validate_calendar(unknown_calendar)

      assert {:error, %Localize.UnknownNumberSystemError{}} =
               Localize.validate_number_system(unknown_number_system)

      refute Localize.available_locale_id?(unknown_locale)

      refute existing_atom?(unknown_calendar)
      refute existing_atom?(unknown_number_system)
      refute existing_atom?(unknown_locale)
    end
  end

  defp existing_atom?(value) do
    _ = String.to_existing_atom(value)
    true
  rescue
    ArgumentError -> false
  end
end
