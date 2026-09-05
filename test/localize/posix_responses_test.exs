defmodule Localize.PosixResponsesTest do
  @moduledoc """
  CLDR's POSIX `yesstr` / `nostr` messages — the forms a locale accepts as
  an affirmative or negative answer at a prompt.
  """

  use ExUnit.Case, async: true

  doctest Localize, only: [affirmative_responses: 1, negative_responses: 1]

  describe "reading the responses" do
    # The values are colon-separated in CLDR, most complete form first.
    test "returns the accepted forms for a locale" do
      assert {:ok, ["yes", "y"]} = Localize.affirmative_responses(:en)
      assert {:ok, ["no", "n"]} = Localize.negative_responses(:en)
      assert {:ok, ["ja", "j"]} = Localize.affirmative_responses(:de)
      assert {:ok, ["nein", "n"]} = Localize.negative_responses(:de)
      assert {:ok, ["oui", "o"]} = Localize.affirmative_responses(:fr)
    end

    # A locale may keep a Latin abbreviation beside a native word.
    test "carries non-Latin forms" do
      assert {:ok, ["はい", "y"]} = Localize.affirmative_responses(:ja)
      assert {:ok, ["いいえ", "n"]} = Localize.negative_responses(:ja)
      assert {:ok, ["نعم", "ن"]} = Localize.affirmative_responses(:ar)
    end

    test "an unknown locale is an error" do
      assert {:error, %Localize.InvalidLocaleError{}} = Localize.affirmative_responses(:nope)
    end
  end

  describe "matching a response" do
    # TR35 stores only the lower-case forms and leaves a consumer to derive
    # the upper-case variants, so matching folds case.
    test "folds case" do
      assert Localize.affirmative?("Ja", locale: :de)
      assert Localize.affirmative?("JA", locale: :de)
      assert Localize.negative?("NEIN", locale: :de)
      assert Localize.affirmative?("YES", locale: :en)
    end

    test "ignores surrounding whitespace" do
      assert Localize.affirmative?("  oui  ", locale: :fr)
      assert Localize.negative?("\tnon\n", locale: :fr)
    end

    test "does not accept another locale's forms" do
      refute Localize.affirmative?("y", locale: :de)
      refute Localize.affirmative?("ja", locale: :en)
      refute Localize.negative?("nein", locale: :fr)
    end

    test "matches the abbreviated form" do
      assert Localize.affirmative?("j", locale: :de)
      assert Localize.affirmative?("o", locale: :fr)
      assert Localize.negative?("n", locale: :en)
    end

    # This sits on the input path, where a prompt needs an answer rather
    # than an exception.
    test "returns false rather than raising on bad input" do
      refute Localize.affirmative?(nil, locale: :en)
      refute Localize.affirmative?("", locale: :en)
      refute Localize.affirmative?(:yes, locale: :en)
      refute Localize.affirmative?(%{}, locale: :en)
      refute Localize.affirmative?("yes", locale: :nope)
      refute Localize.negative?(nil, locale: :en)
    end
  end

  describe "typeValues" do
    # CLDR centralizes the On/Off strings rather than translating them for
    # each boolean BCP 47 key. TR35 shows them beside the key's own name:
    # "Ignore Symbols Sorting: On".
    test "returns the localized boolean keyword names" do
      assert {:ok, "On"} = Localize.Locale.LocaleDisplay.type_value_name(true, locale: :en)
      assert {:ok, "Off"} = Localize.Locale.LocaleDisplay.type_value_name(false, locale: :en)
      assert {:ok, "Ein"} = Localize.Locale.LocaleDisplay.type_value_name("yes", locale: :de)
      assert {:ok, "Aus"} = Localize.Locale.LocaleDisplay.type_value_name("no", locale: :de)
    end

    test "rejects a value that is not boolean" do
      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Locale.LocaleDisplay.type_value_name("maybe", locale: :en)
    end

    test "an unknown locale is an error" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               Localize.Locale.LocaleDisplay.type_value_name(true, locale: :nope)
    end
  end
end
