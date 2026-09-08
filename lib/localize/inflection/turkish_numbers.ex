defmodule Localize.Inflection.TurkishNumbers do
  @moduledoc false

  # Turkish number spellout, sufficient for the vowel-harmony
  # classification of digit-final strings ("1961" harmonizes over
  # "bin dokuz yüz altmış bir"). Mirrors the CLDR Turkish spellout
  # rules for integers.

  @units {"", "bir", "iki", "üç", "dört", "beş", "altı", "yedi", "sekiz", "dokuz"}
  @tens {"", "on", "yirmi", "otuz", "kırk", "elli", "altmış", "yetmiş", "seksen", "doksan"}

  @ordinals %{
    "sıfır" => "sıfırıncı",
    "bir" => "birinci",
    "iki" => "ikinci",
    "üç" => "üçüncü",
    "dört" => "dördüncü",
    "beş" => "beşinci",
    "altı" => "altıncı",
    "yedi" => "yedinci",
    "sekiz" => "sekizinci",
    "dokuz" => "dokuzuncu",
    "on" => "onuncu",
    "yirmi" => "yirminci",
    "otuz" => "otuzuncu",
    "kırk" => "kırkıncı",
    "elli" => "ellinci",
    "altmış" => "altmışıncı",
    "yetmiş" => "yetmişinci",
    "seksen" => "sekseninci",
    "doksan" => "doksanıncı",
    "yüz" => "yüzüncü",
    "bin" => "bininci",
    "milyon" => "milyonuncu",
    "milyar" => "milyarıncı"
  }

  @doc """
  Spells out a non-negative number in Turkish cardinal words.

  """
  def cardinal(number) when is_float(number) do
    integer = trunc(number)

    if number == integer do
      cardinal(integer)
    else
      fraction =
        number
        |> Float.to_string()
        |> String.split(".")
        |> List.last()
        |> String.graphemes()
        |> Enum.map_join(" ", fn digit -> cardinal(String.to_integer(digit)) end)

      cardinal(integer) <> " virgül " <> fraction
    end
  end

  def cardinal(0), do: "sıfır"

  def cardinal(number) when is_integer(number) and number > 0 do
    number |> parts() |> Enum.join(" ") |> String.trim()
  end

  def cardinal(_number), do: ""

  defp parts(0), do: []

  defp parts(number) when number >= 1_000_000_000 do
    scale(number, 1_000_000_000, "milyar")
  end

  defp parts(number) when number >= 1_000_000 do
    scale(number, 1_000_000, "milyon")
  end

  defp parts(number) when number >= 1000 do
    prefix = div(number, 1000)
    lead = if prefix == 1, do: ["bin"], else: parts(prefix) ++ ["bin"]
    lead ++ parts(rem(number, 1000))
  end

  defp parts(number) when number >= 100 do
    prefix = div(number, 100)
    lead = if prefix == 1, do: ["yüz"], else: [elem(@units, prefix), "yüz"]
    lead ++ parts(rem(number, 100))
  end

  defp parts(number) when number >= 10 do
    [elem(@tens, div(number, 10))] ++ parts(rem(number, 10))
  end

  defp parts(number), do: [elem(@units, number)]

  defp scale(number, unit, word) do
    parts(div(number, unit)) ++ [word] ++ parts(rem(number, unit))
  end

  @doc """
  Spells out a non-negative number in Turkish ordinal words
  (the final word takes the ordinal form).

  """
  def ordinal(number) do
    case cardinal(number) |> String.split(" ") |> Enum.reverse() do
      [] ->
        ""

      [last | rest] ->
        [Map.get(@ordinals, last, last) | rest] |> Enum.reverse() |> Enum.join(" ")
    end
  end
end
