defmodule Localize.DateTime.PartialValueMatrixTest do
  @moduledoc """
  Every combination of date and time fields a map can hold, formatted
  through `Localize.DateTime`, `Localize.Date` and `Localize.Time` with no
  format, the standard formats, skeletons and patterns.

  What is checked comes from TR35 and the formatting rules the changelog
  records, not from the formatter's own output: nothing raises; a result is
  a string or an exception with a message; `to_parts/2` joins to
  `to_string/2`; no part is empty; a standard format, or none, never drops
  a field the value holds; and a skeleton or pattern that asks for a field
  the value lacks is an error naming exactly the missing fields.

  """

  use ExUnit.Case, async: true

  @fields [:year, :month, :day, :hour, :minute, :second]
  @instant %{year: 2024, month: 7, day: 6, hour: 14, minute: 30, second: 45}
  @date_fields [:year, :month, :day]
  @time_fields [:hour, :minute, :second]
  @locales [:en, :de, :ja]

  # Every non-empty subset of the six fields, as a list in field order.
  @subsets for n <- 1..63,
               do:
                 for(
                   {field, bit} <- Enum.with_index(@fields),
                   Bitwise.band(n, Bitwise.bsl(1, bit)) != 0,
                   do: field
                 )

  @standard_formats [nil, :short, :medium, :long, :full]
  @skeletons [:y, :yMMM, :yMMMd, :MMMd, :d, :Ed, :j, :jm, :jms, :Hm, :hms, :ms, :yMMMdjm]
  @patterns ["y", "MMM d", "HH:mm", "h:mm a", "y-MM-dd HH:mm:ss", "EEEE"]

  # The calendar fields each pattern or skeleton symbol displays, per TR35's
  # Date Field Symbol Table: a weekday, week or era needs the whole date, and
  # `j` is an hour.
  @symbol_fields %{
    "G" => [:year, :month, :day],
    "y" => [:year],
    "Q" => [:month],
    "M" => [:month],
    "L" => [:month],
    "d" => [:day],
    "E" => [:year, :month, :day],
    "a" => [:hour],
    "h" => [:hour],
    "H" => [:hour],
    "K" => [:hour],
    "k" => [:hour],
    "j" => [:hour],
    "m" => [:minute],
    "s" => [:second]
  }

  describe "no format or a standard format never drops a field" do
    for format <- @standard_formats do
      test "format #{inspect(format)}" do
        failures =
          for locale <- @locales,
              fields <- @subsets,
              module <- modules_for(fields),
              failure <- [check_standard(module, fields, unquote(format), locale)],
              failure != nil,
              do: failure

        assert failures == [], report(failures)
      end
    end
  end

  describe "a skeleton or pattern formats the fields it names or names those missing" do
    for format <- @skeletons ++ @patterns do
      test "format #{inspect(format)}" do
        failures =
          for locale <- @locales,
              fields <- @subsets,
              module <- modules_for(fields),
              failure <- [check_requested(module, fields, unquote(format), locale)],
              failure != nil,
              do: failure

        assert failures == [], report(failures)
      end
    end
  end

  describe "the halves of a partial datetime" do
    # en `yMMM` is "MMM y", `MMMMd` "MMMM d", `j` "h a" and `jm` "h:mm a"; its
    # date-time pattern is "{1}, {0}" and its long "at" pattern
    # "{1} 'at' {0}". de `yMMM` is "MMM y" and `j` "HH 'Uhr'".
    test "join through the locale's date-time pattern" do
      assert Localize.DateTime.to_string(%{year: 2024, month: 7, hour: 14},
               locale: :en,
               prefer: :ascii
             ) == {:ok, "Jul 2024, 2 PM"}

      assert Localize.DateTime.to_string(%{month: 7, day: 6, hour: 14, minute: 30},
               format: :long,
               locale: :en,
               prefer: :ascii
             ) == {:ok, "July 6, 2:30 PM"}

      assert Localize.DateTime.to_string(%{month: 7, day: 6, hour: 14, minute: 30},
               format: :long,
               style: :at,
               locale: :en,
               prefer: :ascii
             ) == {:ok, "July 6 at 2:30 PM"}

      assert Localize.DateTime.to_string(%{year: 2024, month: 7, hour: 14}, locale: :de) ==
               {:ok, "Juli 2024, 14 Uhr"}
    end
  end

  defp modules_for(fields) do
    cond do
      Enum.all?(fields, &(&1 in @date_fields)) -> [Localize.DateTime, Localize.Date]
      Enum.all?(fields, &(&1 in @time_fields)) -> [Localize.DateTime, Localize.Time]
      true -> [Localize.DateTime]
    end
  end

  defp check_standard(module, fields, format, locale) do
    options = if format, do: [format: format, locale: locale], else: [locale: locale]

    case run(module, Map.take(@instant, fields), options) do
      {{:ok, string}, {:ok, parts}} ->
        expected = expected_fields(fields, format)
        problem = parts_problem(string, parts) || dropped_fields(expected, parts, string)
        tag(problem, module, fields, format, locale)

      # A derived skeleton the locale has no format for, such as a minute on
      # its own, is an error rather than a guess.
      {{:error, %Localize.DateTimeUnresolvedFormatError{}},
       {:error, %Localize.DateTimeUnresolvedFormatError{}}} ->
        nil

      other ->
        {module, fields, format, locale, {:unexpected, other}}
    end
  end

  defp check_requested(module, fields, format, locale) do
    required = required_fields(format)
    missing = required -- fields

    case run(module, Map.take(@instant, fields), format: format, locale: locale) do
      {{:ok, string}, {:ok, parts}} when missing == [] ->
        string |> parts_problem(parts) |> tag(module, fields, format, locale)

      {{:ok, string}, _parts} ->
        {module, fields, format, locale, {:formatted_despite_missing, missing, string}}

      {{:error, %Localize.DateTimeInvalidInputError{missing: reported} = error},
       {:error, %Localize.DateTimeInvalidInputError{missing: reported}}}
      when missing != [] ->
        if MapSet.new(reported) == MapSet.new(missing) and is_binary(Exception.message(error)) do
          nil
        else
          {module, fields, format, locale, {:wrong_missing, reported, missing}}
        end

      other ->
        {module, fields, format, locale, {:unexpected, missing, other}}
    end
  end

  defp run(module, value, options) do
    {module.to_string(value, options), module.to_parts(value, options)}
  end

  defp parts_problem(string, parts) do
    cond do
      Enum.map_join(parts, & &1.value) != string -> {:parts_do_not_join, string, parts}
      Enum.any?(parts, &(&1.value == "")) -> {:empty_part, parts}
      true -> nil
    end
  end

  # CLDR's short time formats show hours and minutes only (`en` "h:mm a",
  # `de` "HH:mm"), so a short format leaves out the seconds of a time that
  # has both; every other field a value holds must appear.
  defp expected_fields(fields, :short) do
    if :hour in fields and :minute in fields, do: fields -- [:second], else: fields
  end

  defp expected_fields(fields, _format), do: fields

  defp dropped_fields(fields, parts, string) do
    case fields -- Enum.map(parts, & &1.type) do
      [] -> nil
      dropped -> {:dropped, dropped, string}
    end
  end

  defp tag(nil, _module, _fields, _format, _locale), do: nil
  defp tag(problem, module, fields, format, locale), do: {module, fields, format, locale, problem}

  defp required_fields(format) do
    format
    |> Kernel.to_string()
    |> then(&Regex.replace(~r/\x27[^\x27]*\x27/, &1, ""))
    |> String.graphemes()
    |> Enum.flat_map(&Map.get(@symbol_fields, &1, []))
    |> Enum.uniq()
  end

  defp report(failures) do
    lines =
      failures
      |> Enum.take(25)
      |> Enum.map_join("\n", fn {module, fields, format, locale, problem} ->
        "  #{inspect(module)} #{inspect(fields)} #{inspect(format)} #{locale}: " <>
          inspect(problem, printable_limit: 200, limit: 12)
      end)

    "#{length(failures)} failures\n#{lines}"
  end
end
