defmodule Localize.Locale.LocaleDisplayTest do
  use ExUnit.Case, async: true

  # The ICU data-driven locale display tests require OTP 28+ for
  # correct Unicode NFC normalization behavior. Doctests run on
  # all OTP versions since they test basic functionality.
  doctest Localize.Locale.LocaleDisplay

  # ── ICU Data-Driven Tests ──────────────────────────────────────
  if System.otp_release() >= "28" do
    # Lines with known data issues or unsupported features
    @invalid_test_results [41, 2530, 2527, 2528, 2531]
    @unexpected_root_locale_results [2517, 2512, 2525, 2518, 2515, 2513, 2526, 2514]

    # Features not yet implemented:
    # - uu attribute display in U extension (47)
    # - variant display in T extension for certain locales (ka, ko, kk)
    # - root locale: no translations, raw subtag codes expected
    @not_yet_implemented [
      47,
      627,
      631,
      646,
      650,
      2223,
      2227,
      2242,
      2246,
      2451,
      2455,
      2470,
      2474,
      3514,
      3515,
      3516,
      3517,
      3518,
      3519,
      3520,
      3521,
      3522,
      3524,
      3525,
      3526,
      3533,
      3534,
      3535,
      3536,
      3537,
      3538,
      3539,
      3540,
      3541,
      3543,
      3544,
      3545
    ]

    @except_lines @invalid_test_results ++ @unexpected_root_locale_results ++ @not_yet_implemented

    # Locales with data formatting issues
    @except_format_for_locales ["hi-Latn", "zh-Hans", "zh-Hant", "zh-Hans-fonipa"]

    for [line, locale, language_display, from, to] <-
          Localize.LocaleDisplayNameGenerator.data(),
        line not in @except_lines,
        from not in @except_format_for_locales do
      @tag locale_display_icu: line
      test "ICU ##{line} #{inspect(from)} => #{inspect(to)} in #{inspect(locale)}" do
        result =
          Localize.Locale.LocaleDisplay.display_name(
            unquote(from),
            locale: unquote(locale),
            language_display: unquote(language_display)
          )

        case result do
          {:ok, actual} ->
            assert actual == unquote(to),
                   "Line #{unquote(line)}: expected #{inspect(unquote(to))}, got #{inspect(actual)}"

          {:error, _} ->
            flunk(
              "Line #{unquote(line)}: display_name returned error for #{inspect(unquote(from))}"
            )
        end
      end
    end
  end

  # if OTP 28+

  describe "display_name/2 basic formatting" do
    test "simple language" do
      assert {:ok, "English"} = Localize.Locale.LocaleDisplay.display_name("en")
    end

    test "language with territory in standard mode" do
      assert {:ok, "English (United States)"} =
               Localize.Locale.LocaleDisplay.display_name("en-US")
    end

    test "language with territory in dialect mode" do
      assert {:ok, "American English"} =
               Localize.Locale.LocaleDisplay.display_name("en-US", language_display: :dialect)
    end

    test "compound dialect name" do
      assert {:ok, "Flemish"} =
               Localize.Locale.LocaleDisplay.display_name("nl-BE", language_display: :dialect)
    end

    test "language with script and territory" do
      assert {:ok, name} = Localize.Locale.LocaleDisplay.display_name("zh-Hans-CN")
      assert String.contains?(name, "Chinese")
      assert String.contains?(name, "Simplified")
    end

    test "display in different locale" do
      assert {:ok, "anglais"} = Localize.Locale.LocaleDisplay.display_name("en", locale: :fr)
    end

    test "display in German" do
      {:ok, name} = Localize.Locale.LocaleDisplay.display_name("en-US", locale: :de)
      assert String.contains?(name, "Englisch")
      assert String.contains?(name, "Vereinigte Staaten")
    end
  end

  describe "display_name/2 with U extension" do
    test "calendar and currency extensions in dialect mode" do
      {:ok, name} =
        Localize.Locale.LocaleDisplay.display_name("en-US-u-ca-gregory-cu-aud",
          language_display: :dialect
        )

      assert String.contains?(name, "American English")
      assert String.contains?(name, "Gregorian Calendar")
      assert String.contains?(name, "A$")
    end

    test "calendar extension in French dialect mode" do
      {:ok, name} =
        Localize.Locale.LocaleDisplay.display_name("en-US-u-ca-gregory-cu-aud",
          locale: :fr,
          language_display: :dialect
        )

      assert String.contains?(name, "anglais")
      assert String.contains?(name, "A$")
    end
  end

  describe "display_name/2 with prefer option" do
    test "prefer :short for territory" do
      {:ok, name} =
        Localize.Locale.LocaleDisplay.display_name("en-GB", locale: :"en-GB", prefer: :short)

      assert String.contains?(name, "UK")
    end
  end

  describe "display_name!/2" do
    test "returns string directly" do
      assert "English" = Localize.Locale.LocaleDisplay.display_name!("en")
    end

    test "raises on invalid input" do
      assert_raise Localize.ParseError, fn ->
        Localize.Locale.LocaleDisplay.display_name!("xyz-invalid-totally-bad")
      end
    end
  end

  describe "display_name/2 error handling" do
    test "returns error for unparseable locale" do
      result = Localize.Locale.LocaleDisplay.display_name("xyz-invalid-totally-bad")
      assert match?({:error, _}, result)
    end
  end

  # Regression: `find_exemplar_city/2` (in `LocaleDisplay.U`) and
  # `to_atom_safe/1` (in `LocaleDisplay.T`) used to call
  # `String.to_atom/1` on `-u-tz-` and `-t-` extension values from
  # caller-controlled BCP-47 tags. Atomisation is now gated on
  # `Helpers.existing_atom/1`.
  describe "atom-table bound on extension parsing" do
    test "unknown -t- script does not create an atom" do
      seed = Elixir.System.unique_integer([:positive])
      # 4-letter script subtag form so the grammar accepts it but the
      # validity set rejects it. If parsing rejects, the call returns
      # an error; the important assertion is no atom growth.
      bogus = "Zsx" <> String.upcase(Integer.to_string(rem(seed, 26)))
      _ = Localize.Locale.LocaleDisplay.display_name("en-t-ja-#{bogus}")
      # The parser may downcase or otherwise normalise; check both forms.
      assert nil == Localize.Utils.Helpers.existing_atom(bogus)
      assert nil == Localize.Utils.Helpers.existing_atom(String.downcase(bogus))
    end
  end
end
