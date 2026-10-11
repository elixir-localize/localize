defmodule Localize.NormalizeAltContentTest do
  @moduledoc """
  Covers how `group_alt_content/2` resolves codes that normalize onto one key.

  CLDR gives a display name to both a canonical code and the codes it retired
  in that code's favour — `fil` beside `tl`, `ak` beside `tw` — and the
  normalizer maps all four onto two keys. The merge takes the last entry, so
  the arrival order decides which name a locale ends up with.

  Mapping over the source map left that order to the map's internal one, which
  differs between OTP releases: generating `en` from one CLDR checkout gave
  `fil` the alias's "Tagalog" on OTP 28 and "Filipino" on OTP 29 (issue #59).
  A language map holds 668 keys, well past the 32 where a map becomes a
  hashmap, so the order is the hash's and not the insertion's.

  These tests pin both halves of the fix: the order is the data's rather than
  the runtime's, and the entry whose own code is the key wins.

  """

  use ExUnit.Case, async: true

  alias Localize.Data.Normalize.Helpers

  # The two collisions CLDR's language names actually carry, with the name of
  # the canonical code and of the code retired in its favour.
  @cldr_collisions [
    {"fil", "Filipino", "tl", "Tagalog"},
    {"ak", "Akan", "tw", "Twi"}
  ]

  defp canonical(code) do
    code |> Localize.LanguageTag.parse!() |> Localize.LanguageTag.to_string()
  end

  describe "a code that normalizes onto another code's key" do
    test "does not take that key's name" do
      for {code, name, alias_code, alias_name} <- @cldr_collisions do
        entries = [{code, name}, {alias_code, alias_name}]
        grouped = Helpers.group_alt_content(entries, &canonical/1)

        assert grouped[code]["default"] == name,
               "#{code} took #{inspect(grouped[code]["default"])} from #{alias_code}"
      end
    end

    test "wins whichever order the entries arrive in" do
      for {code, name, alias_code, alias_name} <- @cldr_collisions do
        forward =
          Helpers.group_alt_content([{code, name}, {alias_code, alias_name}], &canonical/1)

        reverse =
          Helpers.group_alt_content([{alias_code, alias_name}, {code, name}], &canonical/1)

        assert forward == reverse
        assert forward[code]["default"] == name
      end
    end
  end

  describe "the order entries arrive in" do
    # The regression proper. Before the fix this function iterated its argument
    # as given, so a map large enough to be a hashmap resolved the collision by
    # hash order while the same entries as a list resolved it by list order.
    # Running on every OTP version in the matrix is what makes this a guard:
    # the hash order it compares against is the one that release produces.
    test "is not the iteration order of a hashmap argument" do
      filler = for n <- 1..40, do: {"filler#{n}", "name #{n}"}
      entries = filler ++ [{"x", "canonical"}, {"alias_x", "aliased"}]

      map = Map.new(entries)
      assert map_size(map) > 32, "the argument must be large enough to be a hashmap"

      normalizer = &String.replace_prefix(&1, "alias_", "")

      from_map = Helpers.group_alt_content(map, normalizer)
      from_sorted_list = Helpers.group_alt_content(Enum.sort(entries), normalizer)
      from_reversed_list = Helpers.group_alt_content(Enum.sort(entries, :desc), normalizer)

      assert from_map == from_sorted_list
      assert from_map == from_reversed_list
      assert from_map["x"]["default"] == "canonical"
    end
  end

  describe "alt and menu variants" do
    test "are still grouped under the code they belong to" do
      grouped =
        Helpers.group_alt_content(
          [
            {"US", "United States"},
            {"US_alt_short", "US"},
            {"GB_alt_variant", "UK"},
            {"HK_menu_china", "China, Hong Kong"}
          ],
          &String.upcase/1
        )

      assert grouped["US"] == %{"default" => "United States", "short" => "US"}
      assert grouped["GB"] == %{"variant" => "UK"}
      assert grouped["HK"] == %{"menu" => %{"china" => "China, Hong Kong"}}
    end

    test "do not displace the default of the code they belong to" do
      grouped =
        Helpers.group_alt_content(
          [{"fil", "Filipino"}, {"tl", "Tagalog"}, {"fil_alt_short", "Fil"}],
          &canonical/1
        )

      assert grouped["fil"] == %{"default" => "Filipino", "short" => "Fil"}
    end
  end
end
