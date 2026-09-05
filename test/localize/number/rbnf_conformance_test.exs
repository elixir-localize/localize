defmodule Localize.Number.RbnfConformanceTest do
  @moduledoc """
  CLDR 49's RBNF conformance suite (`common/testData/rbnf`).

  One `.ssv` file per locale, around 53,000 cases, exercising every public
  rule set. The header of each file gives the format:

      type;rule name;number;expected result
      type: spell=SpelloutRules, digits=OrdinalRules, number=NumberingSystemRules

  A handful of rows in the upstream data carry a stray leading `;`
  (`ga.ssv` line 53, among 23 others); the leading empty field is dropped
  rather than treated as a malformed row.
  """

  use ExUnit.Case, async: true

  @moduletag :conformance
  @moduletag timeout: 600_000

  @data_dir Path.join([__DIR__, "..", "..", "support", "data", "rbnf_conformance"])

  # 52,685 of 52,691 cases match ICU exactly. Six do not, in two classes,
  # both turning on whether a zero remainder is spelled — and pulling in
  # opposite directions, which is why neither has been resolved by guessing.
  #
  #   * `af` `%spellout-numbering-year` (2). ICU renders 1100 as "elf honderd
  #     nul", spelling a trailing zero. `%%2d-year`'s `0: honderd[
  #     >%spellout-numbering>]` omits its optional part on a zero remainder
  #     and yields our "elf honderd"; where ICU's extra "nul" comes from is
  #     not apparent in the rule text.
  #   * `bg` financial cardinals at 9,007,199,254,740,991 (4). We spell "и
  #     нула хиляди" — "and zero thousand" — where ICU omits the zero group
  #     entirely.
  #
  # These are a ratchet, not accepted divergences: neither has been traced to
  # a conflict between CLDR's rules and ICU's behaviour, so they are recorded
  # as unfinished. Contrast `@divergences` in the decimal conformance test,
  # where each entry names what CLDR ships and why we follow it.
  @thresholds %{
    "af" => 2,
    "bg" => 4
  }

  defp locales do
    @data_dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".ssv"))
    |> Enum.map(&{Path.basename(&1, ".ssv") |> String.replace("_", "-"), &1})
    |> Enum.sort()
  end

  defp cases(file) do
    @data_dir
    |> Path.join(file)
    |> File.stream!()
    |> Stream.map(&String.trim_trailing(&1, "\n"))
    |> Stream.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Stream.map(&(&1 |> String.trim_leading(";") |> String.split(";")))
    |> Enum.filter(&match?([_, _, _, _], &1))
  end

  # `%spellout-cardinal` in the fixture is `spellout_cardinal` here, and an
  # empty rule name means the group's default rule set.
  defp rule_name(""), do: :default

  defp rule_name(rule) do
    rule |> String.trim_leading("%") |> String.replace("-", "_")
  end

  defp number(string) do
    case Integer.parse(string) do
      {integer, ""} ->
        integer

      _ ->
        case Float.parse(string) do
          {float, ""} -> float
          _ -> :skip
        end
    end
  end

  test "every locale formats within its known mismatch count" do
    {failures, mismatches} =
      Enum.reduce(locales(), {[], %{}}, fn {locale, file}, acc ->
        Enum.reduce(cases(file), acc, fn [_type, rule, num, expected], {failures, counts} ->
          case number(num) do
            :skip ->
              {failures, counts}

            value ->
              case Localize.Number.Rbnf.to_string(value, rule_name(rule), locale: locale) do
                {:ok, ^expected} ->
                  {failures, counts}

                other ->
                  counts = Map.update(counts, locale, 1, &(&1 + 1))
                  {[{locale, rule, num, expected, other} | failures], counts}
              end
          end
        end)
      end)

    unexpected =
      Enum.reject(mismatches, fn {locale, count} -> count <= Map.get(@thresholds, locale, 0) end)

    assert unexpected == [],
           """
           #{length(failures)} mismatches; these locales exceed their known counts:
           #{Enum.map_join(unexpected, "\n", fn {locale, count} -> "  #{locale}: #{count}, expected at most #{Map.get(@thresholds, locale, 0)}" end)}

           #{failures |> Enum.filter(fn {locale, _, _, _, _} -> Enum.any?(unexpected, &(elem(&1, 0) == locale)) end) |> Enum.take(10) |> Enum.map_join("\n", fn {locale, rule, num, expected, got} -> "  #{locale} #{rule} #{num}: expected #{inspect(expected)}, got #{inspect(got)}" end)}
           """

    improved =
      Enum.reject(@thresholds, fn {locale, threshold} ->
        Map.get(mismatches, locale, 0) == threshold
      end)

    assert improved == [],
           "These locales now have fewer mismatches than recorded — lower the " <>
             "thresholds: #{inspect(improved)} vs actual " <>
             "#{inspect(Map.take(mismatches, Enum.map(improved, &elem(&1, 0))))}"
  end
end
