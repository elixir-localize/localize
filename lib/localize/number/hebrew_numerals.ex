defmodule Localize.Number.HebrewNumerals do
  @moduledoc false

  # Reads a number written in Hebrew numerals, the `hebr` numbering system,
  # as CLDR's `hebrew` rule set writes it: the letters' values added up,
  # from the largest to the smallest ("תשפ״ד" is 400 + 300 + 80 + 4); a
  # geresh after letters that more letters follow marking those letters as
  # thousands ("ה׳תשפ״ד" is 5784); and a whole number of thousands written
  # with the word for them ("ה׳ אלפים" is 5000, "אלף" 1000). The geresh and
  # gershayim (׳ and ״, or ' and ") only punctuate. Letters whose values
  # rise, or repeat other than 400, are no numeral, so a word ("בטבת") is
  # not read as one.

  @values %{
    "א" => 1,
    "ב" => 2,
    "ג" => 3,
    "ד" => 4,
    "ה" => 5,
    "ו" => 6,
    "ז" => 7,
    "ח" => 8,
    "ט" => 9,
    "י" => 10,
    "כ" => 20,
    "ך" => 20,
    "ל" => 30,
    "מ" => 40,
    "ם" => 40,
    "נ" => 50,
    "ן" => 50,
    "ס" => 60,
    "ע" => 70,
    "פ" => 80,
    "ף" => 80,
    "צ" => 90,
    "ץ" => 90,
    "ק" => 100,
    "ר" => 200,
    "ש" => 300,
    "ת" => 400
  }

  @punctuation ["׳", "״", "'", "\""]
  @thousand "אלף"
  @thousands "אלפים"

  @doc false
  # The source of a regex that matches the numerals `parse/1` reads.
  @spec regex_source() :: String.t()
  def regex_source, do: "[א-ת׳״'\"]+(?: #{@thousands})?"

  @doc false
  @spec parse(term()) :: {:ok, pos_integer()} | :error
  def parse(@thousand), do: {:ok, 1000}

  def parse(string) when is_binary(string) do
    case String.split(string, " ") do
      [count, @thousands] ->
        with {:ok, thousands} <- letters(count), do: {:ok, thousands * 1000}

      [numeral] ->
        numeral(numeral)

      _other ->
        :error
    end
  end

  def parse(_other), do: :error

  defp numeral(string) do
    case Regex.run(~r/\A([^׳']+)[׳']([א-ת].*)\z/u, string, capture: :all_but_first) do
      [thousands, rest] ->
        with {:ok, thousands} <- letters(thousands),
             {:ok, rest} <- letters(rest),
             do: {:ok, thousands * 1000 + rest}

      nil ->
        letters(string)
    end
  end

  defp letters(string) do
    values =
      string
      |> String.graphemes()
      |> Enum.reject(&(&1 in @punctuation))
      |> Enum.map(&Map.get(@values, &1))

    if values != [] and Enum.all?(values, &is_integer/1) and descending?(values),
      do: {:ok, Enum.sum(values)},
      else: :error
  end

  defp descending?([first, second | rest])
       when first > second or (first == 400 and second == 400),
       do: descending?([second | rest])

  defp descending?([_last]), do: true
  defp descending?(_rising), do: false
end
