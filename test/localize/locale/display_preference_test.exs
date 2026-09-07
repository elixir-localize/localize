defmodule Localize.Locale.DisplayPreferenceTest do
  use ExUnit.Case, async: true

  alias Localize.Locale.LocaleDisplay

  describe ":prefer and :style name the same option" do
    test "Localize.Language accepts both" do
      assert LocaleDisplay.key_name(:ca, locale: :en) == {:ok, "Calendar"}
      assert Localize.Language.display_name("en-GB", prefer: :short) == {:ok, "UK English"}

      assert Localize.Language.display_name("en-GB", style: :short) ==
               Localize.Language.display_name("en-GB", prefer: :short)
    end

    test "Localize.Territory accepts both" do
      assert Localize.Territory.display_name(:GB, prefer: :short) == {:ok, "UK"}

      assert Localize.Territory.display_name(:GB, style: :short) ==
               Localize.Territory.display_name(:GB, prefer: :short)
    end

    test "Localize.Script accepts both" do
      assert Localize.Script.display_name(:Hans, prefer: :stand_alone) ==
               {:ok, "Simplified Han"}

      assert Localize.Script.display_name(:Hans, style: :stand_alone) ==
               Localize.Script.display_name(:Hans, prefer: :stand_alone)
    end

    test ":prefer wins when both are given" do
      assert Localize.Territory.display_name(:GB, style: :standard, prefer: :short) ==
               {:ok, "UK"}
    end
  end

  # TR35 treats `alt="menu"` and the `menu="core"` / `menu="extension"` pair
  # as separate parameters. `PreferAlt` selects the locale's own composed
  # string; `CoreAndExtension` composes the halves through `localePattern`.
  # Of 2,589 menu entries across the 657 locales, 1,893 carry only the alt,
  # 571 only the halves, and 125 both.
  describe "prefer: :menu" do
    test "takes the locale's own alt=menu string when there is one" do
      assert Localize.Language.display_name("ckb", prefer: :menu) == {:ok, "Kurdish, Central"}
      assert Localize.Language.display_name("zh", prefer: :menu) == {:ok, "Chinese, Mandarin"}
    end

    # Regression: these returned the unqualified name ("Kurdish", "Southern
    # Kurdish") because only `:alt` was read, so the 571 entries that ship
    # just the two halves lost their menu form entirely.
    test "composes core and extension when the locale ships no alt" do
      assert Localize.Language.display_name("ku", prefer: :menu) == {:ok, "Kurdish (Kurmanji)"}
      assert Localize.Language.display_name("sdh", prefer: :menu) == {:ok, "Kurdish (Southern)"}
    end

    test "falls back to the unqualified name where CLDR has no menu form" do
      assert Localize.Language.display_name("en", prefer: :menu) == {:ok, "English"}
    end

    # A whole locale identifier puts the extension in the same parenthesised
    # list as the script and territory subtags, so `CoreAndExtension` applies
    # here even for a language that also has an alt.
    test "display_name/2 composes rather than taking the alt" do
      assert LocaleDisplay.display_name("ckb", prefer: :menu) == {:ok, "Kurdish (Central)"}
    end
  end

  describe "preference validation" do
    test "an unsupported value is reported, not silently ignored" do
      assert {:error, %Localize.InvalidValueError{value: :core, allowed_values: allowed}} =
               LocaleDisplay.display_name("en-US", prefer: :core)

      assert :standard in allowed
      refute :core in allowed
    end

    # `:default` used to be accepted as an undocumented alias for
    # `:standard`. CLDR has no name for the unqualified entry — cldr-json
    # emits it as a bare key — and `"default"` is only a transient label in
    # our own normalizers, renamed to `"standard"` before the data is stored.
    test ":default is no longer accepted" do
      assert {:error, %Localize.InvalidValueError{value: :default}} =
               LocaleDisplay.display_name("en-US", prefer: :default)
    end

    test "each module reports its own supported subset" do
      assert {:error, %Localize.InvalidValueError{allowed_values: allowed}} =
               Localize.Script.display_name(:Hans, prefer: :menu)

      assert :stand_alone in allowed
      refute :menu in allowed
    end

    test "a valid preference still renders" do
      assert {:ok, "English (US)"} = LocaleDisplay.display_name("en-US", prefer: :short)
    end
  end

  describe "key_name/2" do
    test "accepts the short and long spellings of a key" do
      assert LocaleDisplay.key_name(:ca, locale: :en) == {:ok, "Calendar"}
      assert LocaleDisplay.key_name(:calendar, locale: :en) == {:ok, "Calendar"}
    end

    test "is localized" do
      assert {:ok, name} = LocaleDisplay.key_name(:ms, locale: :de)
      assert name == "Maßsystem"
    end

    test "returns an error for an unknown key" do
      assert {:error, %Localize.ItemNotFoundError{}} = LocaleDisplay.key_name(:zz, locale: :en)
    end

    # Keys arrive from callers, so an unknown one must not reach
    # `String.to_atom/1`. Asserting on the specific string rather than a
    # global atom count, which drifts for unrelated reasons.
    test "a caller-supplied binary is never interned" do
      seed = System.unique_integer([:positive])
      bogus = "no-such-key-#{seed}"

      assert {:error, %Localize.ItemNotFoundError{}} = LocaleDisplay.key_name(bogus, locale: :en)
      assert nil == Localize.Utils.Helpers.existing_atom(bogus)
    end
  end

  describe "type_name/3" do
    test "returns the full name of a key's type value" do
      assert LocaleDisplay.type_name(:ca, :buddhist, locale: :en) == {:ok, "Buddhist Calendar"}

      assert LocaleDisplay.type_name(:co, :phonebook, locale: :en) ==
               {:ok, "Phonebook Sort Order"}
    end

    # The short names CLDR marks `scope="core"` are collapsed by cldr-json
    # onto a single `core` entry per key, so the name belonging to a given
    # value cannot be recovered. Returning the surviving entry would hand
    # back a name belonging to some other type.
    test "prefer: :menu returns an error rather than another type's name" do
      assert {:error, %Localize.ItemNotFoundError{}} =
               LocaleDisplay.type_name(:ca, :buddhist, locale: :en, prefer: :menu)
    end

    test "rejects a preference it cannot supply" do
      assert {:error, %Localize.InvalidValueError{value: :short}} =
               LocaleDisplay.type_name(:ca, :buddhist, locale: :en, prefer: :short)
    end

    test "returns an error for an unknown value" do
      assert {:error, %Localize.ItemNotFoundError{}} =
               LocaleDisplay.type_name(:ca, :nonexistent, locale: :en)
    end

    test "tolerates nil and garbage without raising" do
      assert {:error, _} = LocaleDisplay.type_name(nil, nil, locale: :en)
      assert {:error, _} = LocaleDisplay.type_name(:ca, "", locale: :en)
      assert {:error, _} = LocaleDisplay.type_name(%{}, [], locale: :en)
    end
  end
end
