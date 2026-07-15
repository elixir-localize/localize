defmodule Localize.LanguageTag.LikelySubtagsTest do
  use ExUnit.Case, async: true

  alias Localize.LanguageTag

  @test_data_path Path.join([
                    __DIR__,
                    "..",
                    "..",
                    "support",
                    "data",
                    "likely_subtags_test_data.txt"
                  ])

  @moduletag :likely_subtags

  # Parse the CLDR test data file into a list of
  # {source, add_likely, remove_favor_script, remove_favor_region} tuples.
  @test_cases @test_data_path
              |> File.read!()
              |> String.split("\n")
              |> Enum.reject(fn line ->
                String.starts_with?(line, "#") or String.trim(line) == ""
              end)
              |> Enum.map(fn line ->
                parts =
                  line
                  |> String.split(";")
                  |> Enum.map(&String.trim/1)

                source = Enum.at(parts, 0)
                add_likely = Enum.at(parts, 1, "")
                remove_script = Enum.at(parts, 2, "")
                remove_region = Enum.at(parts, 3, "")

                # Empty RemoveFavorScript means same as AddLikely
                # Empty RemoveFavorRegion means same as RemoveFavorScript
                remove_script = if remove_script == "", do: add_likely, else: remove_script
                remove_region = if remove_region == "", do: remove_script, else: remove_region

                {source, add_likely, remove_script, remove_region}
              end)

  @skip_sources MapSet.new([])

  describe "add_likely_subtags against CLDR test data" do
    for {source, expected_add, _remove_script, _remove_region} <- @test_cases,
        source not in @skip_sources,
        expected_add != "FAIL" do
      @tag_source source
      @tag_expected expected_add

      test "add_likely_subtags(#{source}) == #{expected_add}" do
        {:ok, tag} = LanguageTag.parse(@tag_source)
        {:ok, result} = LanguageTag.add_likely_subtags(tag)
        assert result.canonical_locale_id == @tag_expected
      end
    end
  end

  describe "remove_likely_subtags (favor script) against CLDR test data" do
    for {source, expected_add, expected_remove, _remove_region} <- @test_cases,
        source not in @skip_sources,
        expected_add != "FAIL" do
      @tag_source source
      @tag_expected_remove expected_remove

      test "remove_likely_subtags(#{source}) == #{expected_remove}" do
        {:ok, tag} = LanguageTag.parse(@tag_source)
        {:ok, result} = LanguageTag.remove_likely_subtags(tag)
        assert result.canonical_locale_id == @tag_expected_remove
      end
    end
  end

  describe "remove_likely_subtags (favor region) against CLDR test data" do
    for {source, expected_add, _remove_script, expected_remove_region} <- @test_cases,
        source not in @skip_sources,
        expected_add != "FAIL" do
      @tag_source source
      @tag_expected_remove_region expected_remove_region

      test "remove_likely_subtags(#{source}, favor: :region) == #{expected_remove_region}" do
        {:ok, tag} = LanguageTag.parse(@tag_source)
        {:ok, result} = LanguageTag.remove_likely_subtags(tag, favor: :region)
        assert result.canonical_locale_id == @tag_expected_remove_region
      end
    end
  end

  describe "remove_likely_subtags :favor option validation" do
    test "an invalid :favor value returns an error tuple" do
      {:ok, tag} = LanguageTag.parse("zh-Hant-TW")

      assert {:error, %Localize.InvalidValueError{} = error} =
               LanguageTag.remove_likely_subtags(tag, favor: :language)

      assert Exception.message(error) =~ ":script"
    end
  end

  describe "FAIL rows against CLDR test data" do
    # Rows whose expected AddLikely value is the literal "FAIL" have
    # no likely-subtags mapping. TR35 permits either signalling an
    # error or returning the input unmodified — what it forbids is
    # fabricating subtags. The assertion is therefore that the result
    # (when not an error) is identical to the canonicalized input.
    for {source, "FAIL", _remove_script, _remove_region} <- @test_cases,
        source not in @skip_sources do
      @tag_source source

      test "add_likely_subtags(#{source}) does not invent subtags" do
        {:ok, tag} = LanguageTag.parse(@tag_source)
        {:ok, canonical} = LanguageTag.canonicalize(tag)

        case LanguageTag.add_likely_subtags(canonical) do
          {:error, _} ->
            :ok

          {:ok, result} ->
            assert result.canonical_locale_id == canonical.canonical_locale_id
        end
      end
    end
  end
end
