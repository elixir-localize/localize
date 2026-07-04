defmodule Localize.LocaleCanonicalizationTest do
  use ExUnit.Case, async: true

  @moduledoc false

  alias Localize.LanguageTag

  # TR35 Annex C "Territory Exception": multi-replacement territory
  # aliases are disambiguated by the base language's likely territory
  # when it appears in the replacement list, otherwise the first
  # entry. The CLDR test file only exercises `und-SU`-style inputs,
  # which never trigger the disambiguation, so these are hand-written.
  describe "multi-replacement territory alias disambiguation" do
    @annex_c_cases [
      {"hy-SU", "hy-AM"},
      {"ru-SU", "ru-RU"},
      {"und-SU", "und-RU"},
      {"uk-SU", "uk-UA"},
      {"kk-SU", "kk-KZ"},
      {"tg-SU", "tg-TJ"},
      {"sr-YU", "sr-RS"},
      {"sr-CS", "sr-RS"}
    ]

    for {source, expected} <- @annex_c_cases do
      test "#{source} canonicalizes to #{expected}" do
        assert {:ok, tag} = Localize.validate_locale(unquote(source))
        assert tag.canonical_locale_id == unquote(expected)
      end
    end
  end

  @data_file Path.join([__DIR__, "..", "support", "data", "locale_canonicalization.txt"])

  @test_cases @data_file
              |> File.read!()
              |> String.split("\n")
              |> Enum.reject(fn line ->
                trimmed = String.trim(line)
                trimmed == "" or String.starts_with?(trimmed, "#")
              end)
              |> Enum.map(fn line ->
                [source, expected] =
                  line
                  |> String.split(";")
                  |> Enum.map(&String.trim/1)

                {source, expected}
              end)

  describe "locale canonicalization against CLDR test data" do
    for {source, expected} <- @test_cases do
      @tag_source source
      @tag_expected expected

      test "canonicalize(#{source}) == #{expected}" do
        locale_id =
          @tag_source
          |> String.replace("_", "-")

        expected =
          @tag_expected
          |> String.replace("_", "-")

        case LanguageTag.parse(locale_id) do
          {:ok, tag} ->
            case LanguageTag.canonicalize(tag) do
              {:ok, canonical} ->
                assert canonical.canonical_locale_id == expected,
                       "Expected #{inspect(expected)}, got #{inspect(canonical.canonical_locale_id)} for input #{inspect(@tag_source)}"

              {:error, reason} ->
                flunk("Canonicalization failed for #{inspect(@tag_source)}: #{inspect(reason)}")
            end

          {:error, _reason} ->
            flunk("Parse failed for #{inspect(@tag_source)}")
        end
      end
    end
  end
end
