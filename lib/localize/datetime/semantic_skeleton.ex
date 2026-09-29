defmodule Localize.DateTime.SemanticSkeleton do
  @moduledoc """
  TR35 semantic skeletons: asking for a date or time by *meaning* rather
  than by which fields to render.

  A classical skeleton such as `:yMMMd` is an instruction — year, abbreviated
  month, day. A semantic skeleton is a request: "year, month, day and
  weekday, at medium length", written `YMDE`. The library then chooses the
  fields, and a locale is free to choose differently.

  CLDR ships no semantic skeleton data. TR35 §Mapping to Standard Skeletons
  resolves one from data Localize already has: the year, month and day take
  their widths from the locale's own date format at the requested length,
  and the weekday, time and zone come from a fixed table. So a medium date is
  `yMMMd` in `en` but `yMMdd` in `de`, whose medium date is numeric. The
  datetime conformance data, the one file in CLDR that mentions semantic
  skeletons, pairs each of its cases with the classical skeleton it resolves
  to, and every case resolves as it says.

  ## Field codes

  The skeleton code names the fields wanted:

  * `Y` — year

  * `M` — month

  * `D` — day of the month

  * `E` — day of the week

  * `T` — time

  * `Z` — time zone

  So `YMD` is a plain date, `YMDE` adds the weekday, `T` is a time on its
  own, and `MDTZ` is a month, day, time and zone together.

  The codes name a set, so their order does not matter, and TR35 defines
  which sets there are: a date — `D`, `E`, `DE`, `MD`, `MDE`, `YMD` or
  `YMDE`; a calendar period — `Y`, `M` or `YM`; a time, `T`; and a zone,
  `Z`. A date may be joined to a time, a zone or both (`YMDT`, `MDZ`,
  `ETZ`) and a time to a zone (`TZ`), but a calendar period stands alone.
  Any other set, such as `YD` or `YMT`, is an error, as TR35 requires.

  ## Usage

      import Localize.DateTime.SemanticSkeleton, only: [semantic: 1, semantic: 2]

      Localize.DateTime.to_string(datetime, format: semantic("YMDE"))

      Localize.DateTime.to_string(datetime,
        format: semantic("MDTZ", length: :long, zone_style: :generic))

  The struct is accepted anywhere `:format` is, alongside the standard
  styles, classical skeletons and literal patterns it already took. Building
  it once and reusing it across calls is cheaper than re-validating a
  keyword list each time.

  """

  import Localize.Utils.Helpers, only: [is_keyword_list: 1]

  defstruct fields: [],
            length: :medium,
            year_style: :auto,
            zone_style: :specific,
            zone_length: :auto,
            hour_cycle: :auto,
            time_precision: :second,
            alignment: :inline

  @type field :: :year | :month | :day | :weekday | :time | :zone

  @type time_precision ::
          :hour | :minute | :minute_optional | :second | {:fractional_second, 1..9}

  @type t :: %__MODULE__{
          fields: [field()],
          length: :short | :medium | :long,
          year_style: :auto | :full | :with_era,
          zone_style: :specific | :generic | :location | :offset,
          zone_length: :auto | :short | :long,
          hour_cycle: :auto | :clock12 | :clock24 | :h11 | :h12 | :h23 | :h24,
          time_precision: time_precision(),
          alignment: :inline | :column
        }

  @codes %{
    ?Y => :year,
    ?M => :month,
    ?D => :day,
    ?E => :weekday,
    ?T => :time,
    ?Z => :zone
  }

  @lengths [:short, :medium, :long]
  @year_styles [:auto, :full, :with_era]
  @zone_styles [:specific, :generic, :location, :offset]
  @zone_lengths [:auto, :short, :long]
  @hour_cycles [:auto, :clock12, :clock24, :h11, :h12, :h23, :h24]
  @time_precisions [:hour, :minute, :minute_optional, :second]

  # The exact cycles substitute their symbol into the matched pattern; the
  # clock preferences take the pattern as the locale writes it.
  @exact_hour_cycles %{h11: "K", h12: "h", h23: "H", h24: "k"}
  @twelve_hour_cycles [:clock12, :h11, :h12]
  @twenty_four_hour_cycles [:clock24, :h23, :h24]
  @alignments [:inline, :column]

  # The fields column alignment widens from one letter to two: the numeric
  # month, day and hour.
  @column_padded_symbols ~w(M L d h H K k)

  # The symbols of a date format's skeleton that make up each semantic date
  # field. An era travels with the year, as does the Chinese calendar's
  # related Gregorian year.
  @year_symbols ~c"GyYuUr"
  @month_symbols ~c"ML"

  @date_fields [:year, :month, :day, :weekday]

  # TR35 §Semantic Field Sets. A date names a particular day and a calendar
  # period a span longer than one; a date may be joined to a time, a zone or
  # both, and a time to a zone, while a calendar period stands alone. Each
  # set is held in the order of `@codes`.
  @date_field_sets [
    [:day],
    [:weekday],
    [:day, :weekday],
    [:month, :day],
    [:month, :day, :weekday],
    [:year, :month, :day],
    [:year, :month, :day, :weekday]
  ]

  @calendar_period_field_sets [[:month], [:year], [:year, :month]]

  @field_sets @date_field_sets ++
                @calendar_period_field_sets ++
                [[:time], [:zone], [:time, :zone]] ++
                for(
                  date <- @date_field_sets,
                  joined <- [[:time], [:zone], [:time, :zone]],
                  do: date ++ joined
                )

  @field_order %{year: 0, month: 1, day: 2, weekday: 3, time: 4, zone: 5}
  @field_letters Map.new(@codes, fn {letter, field} -> {field, letter} end)

  @field_set_codes Enum.map(@field_sets, fn field_set ->
                     for field <- field_set, into: "", do: <<Map.fetch!(@field_letters, field)>>
                   end)

  # The fields TR35 names for each option: giving one for a field set that
  # holds none of them is an error. `:length` applies to every field, so to
  # every set, and `:zone_length`, Localize's own, applies to the zone as
  # `:zone_style` does.
  @option_fields [
    alignment: {[:year, :month, :day, :time], "a year, month, day or time"},
    year_style: {[:year], "a year"},
    hour_cycle: {[:time], "a time"},
    time_precision: {[:time], "a time"},
    zone_style: {[:zone], "a zone"},
    zone_length: {[:zone], "a zone"}
  ]

  @doc """
  Builds a semantic skeleton.

  ### Arguments

  * `code` is a string of field codes such as `"YMDE"` or `"MDTZ"`, or a
    list of field atoms such as `[:year, :month, :day]`.

  * `options` is a keyword list.

  ### Options

  * `:length` is `:short`, `:medium` (the default) or `:long`. It says how
    much space the result has, and the locale's own date format at that
    length sets the widths of the year, month and day — `:short` is usually
    numeric, `:long` spells the month out.

  * `:year_style` is `:auto` (the default), `:full` or `:with_era`. `:auto`
    takes the year as the locale's date format writes it, era and all;
    `:full` never truncates it to two digits; `:with_era` also shows the era.

  * `:zone_style` is `:specific` (the default), `:generic`, `:location` or
    `:offset`.

  * `:zone_length` is `:auto` (the default), `:short` or `:long`. `:auto` is
    TR35's rule: a zone on its own takes the long form except at short
    length, and a zone beside other fields the short one. `:short` and
    `:long` choose the form outright — `z` or `zzzz` for a specific zone, `v`
    or `vvvv` for a generic one, `O` or `OOOO` for an offset — which TR35
    does not provide for but MessageFormat 2's `timeZoneStyle` needs. A
    location zone has one form.

  * `:hour_cycle` is `:auto` (the default), `:clock12`, `:clock24`, `:h11`,
    `:h12`, `:h23` or `:h24`, in TR35's vocabulary. `:auto` uses the locale's
    own cycle, which is what a semantic request usually means. `:clock12` and
    `:clock24` ask for a 12- or 24-hour clock and then take the locale's
    pattern as it stands, so `ja` renders `K` rather than `h`. The four exact
    cycles substitute their hour symbol into the matched pattern — `:h11` `K`,
    `:h12` `h`, `:h23` `H`, `:h24` `k` — which is the only way to be sure
    which symbol you get.

  * `:time_precision` is `:hour`, `:minute`, `:minute_optional`, `:second`
    (the default) or `{:fractional_second, digits}` with `digits` from 1 to
    9. `:minute_optional` drops the minutes when they are zero.

  * `:alignment` is `:inline` (the default) or `:column`, TR35's two
    alignments. `:column` is for dates and times set in a column, where
    equal widths line up: it pads a numeric month, day and hour to two
    digits, so `en`'s short date "1/5/25" becomes "01/05/25". It never
    turns a number into text or back, and it acts on the pattern the
    skeleton resolves to, leaving the classical skeleton as it is.

  Each option shapes certain fields, and TR35 makes giving one for a field
  set that has none of them an error: `:year_style` needs `Y`, `:hour_cycle`
  and `:time_precision` need `T`, `:zone_style` and `:zone_length` need `Z`,
  and `:alignment` needs `Y`, `M`, `D` or `T`. `:length` suits every set.

  ### Returns

  * `{:ok, skeleton}`.

  * `{:error, exception}` if a field code or option value is unknown, the
    fields are not a set TR35 defines, or an option is given for a set
    without the fields it applies to.

  ### Examples

      iex> {:ok, skeleton} = Localize.DateTime.SemanticSkeleton.new("YMDE")
      iex> skeleton.fields
      [:year, :month, :day, :weekday]

      iex> Localize.DateTime.SemanticSkeleton.new("YMDQ")
      {:error, %Localize.InvalidValueError{value: "Q", expected: "one of Y, M, D, E, T, Z", context: "Localize.DateTime.SemanticSkeleton"}}

  """
  @spec new(String.t() | [field()], Keyword.t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(code, options \\ [])

  def new(code, options) when is_binary(code) and is_keyword_list(options) do
    with :ok <- validate_code(code),
         {:ok, fields} <- parse_code(code) do
      build(fields, options, code)
    end
  end

  def new(fields, options) when is_list(fields) and is_keyword_list(options) do
    build(fields, options, fields)
  end

  def new(_code, options) when not is_keyword_list(options),
    do: {:error, Localize.Utils.Helpers.invalid_options(options)}

  def new(code, _options) do
    {:error,
     Localize.InvalidValueError.exception(
       value: code,
       expected: "a field code string or a list of fields",
       context: "Localize.DateTime.SemanticSkeleton"
     )}
  end

  @doc """
  Builds a semantic skeleton, raising on invalid input.

  Intended for the `:format` option, where the skeleton is usually a literal
  and a mistake in it is a programming error rather than bad data.

  ### Arguments

  * See `new/2`.

  ### Returns

  * A `t:t/0`.

  ### Raises

  * `Localize.InvalidValueError` wherever `new/2` returns an error.

  ### Examples

      iex> skeleton = Localize.DateTime.SemanticSkeleton.semantic("YMD", length: :long)
      iex> {skeleton.fields, skeleton.length}
      {[:year, :month, :day], :long}

  """
  @spec semantic(String.t() | [field()], Keyword.t()) :: t()
  def semantic(code, options \\ []) do
    case new(code, options) do
      {:ok, skeleton} -> skeleton
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Returns the classical skeleton a semantic skeleton resolves to.

  This is TR35 §Mapping to Standard Skeletons: the year, month and day take
  their widths from the locale's date format at the skeleton's length, the
  weekday, time and zone come from a fixed table, and the time precision and
  year style then adjust the result. The result is an ordinary skeleton
  atom, resolved from there by the machinery that already handles
  `format: :yMMMd`.

  ### Arguments

  * `skeleton` is a `t:t/0`.

  * `options` is a keyword list.

  ### Options

  * `:locale` is the locale whose date formats set the widths of the year,
    month and day. The default is `Localize.get_locale/0`.

  * `:calendar` is a calendar module, `Calendar.ISO` by default. Its CLDR
    calendar type selects the date formats, so a year in a calendar that
    counts years by era carries one.

  * `:value` is the date or time being formatted. Only `:minute_optional`
    precision consults it, dropping the minutes when they are zero; without
    a value the minutes are shown.

  ### Returns

  * `{:ok, atom}` — the classical skeleton.

  * `{:error, exception}` if the skeleton is not one `new/2` builds, as a
    struct made by hand may not be, or the locale or calendar is not known.

  ### Examples

      iex> skeleton = Localize.DateTime.SemanticSkeleton.semantic("YMDE", length: :short)
      iex> Localize.DateTime.SemanticSkeleton.to_classical_skeleton(skeleton, locale: :en)
      {:ok, :yyMdEEE}

      iex> skeleton = Localize.DateTime.SemanticSkeleton.semantic("YMD")
      iex> Localize.DateTime.SemanticSkeleton.to_classical_skeleton(skeleton, locale: :de)
      {:ok, :yMMdd}

      iex> skeleton = Localize.DateTime.SemanticSkeleton.semantic("T", time_precision: :minute)
      iex> Localize.DateTime.SemanticSkeleton.to_classical_skeleton(skeleton, locale: :en)
      {:ok, :jm}

  """
  @spec to_classical_skeleton(t(), Keyword.t()) :: {:ok, atom()} | {:error, Exception.t()}
  def to_classical_skeleton(skeleton, options \\ [])

  def to_classical_skeleton(%__MODULE__{} = skeleton, options) when is_keyword_list(options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())

    with {:ok, locale_id} <- Localize.Locale.cldr_locale_id_from(locale),
         {:ok, calendar} <- Localize.Date.Parser.calendar_option(options) do
      calendar_type = Localize.Date.Parser.cldr_calendar_type(calendar)
      classical_skeleton(skeleton, locale_id, calendar_type, Keyword.get(options, :value))
    end
  end

  def to_classical_skeleton(%__MODULE__{}, options),
    do: {:error, Localize.Utils.Helpers.invalid_options(options)}

  def to_classical_skeleton(skeleton, _options) do
    {:error,
     Localize.InvalidValueError.exception(
       value: skeleton,
       expected: "a Localize.DateTime.SemanticSkeleton",
       context: "Localize.DateTime.SemanticSkeleton.to_classical_skeleton/2"
     )}
  end

  @doc false
  # The formatters' entry point: they have the CLDR locale id and calendar
  # type in hand already, and the value being formatted.
  @spec classical_skeleton(t(), atom(), atom(), term()) ::
          {:ok, atom()} | {:error, Exception.t()}
  def classical_skeleton(%__MODULE__{} = skeleton, locale_id, calendar_type, value) do
    with {:ok, skeleton} <- validate_skeleton(skeleton),
         {:ok, widths} <- date_widths(skeleton, locale_id, calendar_type) do
      pattern = Enum.map_join(skeleton.fields, &field_pattern(&1, skeleton, widths, value))

      # The pieces come from CLDR's date formats and from fixed tables keyed
      # by validated options, so the atoms this can create are a closed set.
      {:ok, String.to_atom(pattern)}
    end
  end

  @doc false
  # TR35 counts a locale's standard date formats among the patterns a
  # skeleton is matched against, and a semantic date resolves to exactly the
  # skeleton of the standard format at its length, since that is where its
  # widths come from. So a semantic skeleton whose date fields resolve to a
  # standard format's skeleton renders with that format: `YMD` is the date
  # format at its length and `YMDE` at long length the full one, even where
  # CLDR's `datetimeSkeleton` misdescribes its own pattern, as `be`'s medium
  # `yMMd` does for "d MMM y 'g'.". The result names the format and the
  # semantic skeleton of any time fields beside it.
  @spec standard_date_format(t(), atom(), atom()) ::
          {:ok, :short | :medium | :long | :full, t() | nil} | :error
  def standard_date_format(%__MODULE__{} = skeleton, locale_id, calendar_type) do
    with {:ok, skeleton} <- validate_skeleton(skeleton),
         {date_fields, time_fields} = Enum.split_with(skeleton.fields, &(&1 in @date_fields)),
         true <- Enum.all?([:year, :month, :day], &(&1 in date_fields)),
         date_skeleton = %{skeleton | fields: date_fields},
         {:ok, classical} <- classical_skeleton(date_skeleton, locale_id, calendar_type, nil),
         {:ok, formats} <- Localize.DateTime.Format.date_formats(locale_id, calendar_type),
         format when not is_nil(format) <-
           Enum.find([skeleton.length, :full], &same_fields?(Map.get(formats, &1), classical)) do
      {:ok, format, time_part(skeleton, time_fields)}
    else
      _no_standard_format -> :error
    end
  end

  def standard_date_format(_skeleton, _locale_id, _calendar_type), do: :error

  defp time_part(_skeleton, []), do: nil
  defp time_part(skeleton, time_fields), do: %{skeleton | fields: time_fields}

  # Two skeletons name the same fields at the same widths, in any order.
  defp same_fields?(first, second)
       when is_atom(first) and not is_nil(first) and is_atom(second) do
    field_runs(first) == field_runs(second)
  end

  defp same_fields?(_first, _second), do: false

  defp field_runs(skeleton) do
    skeleton
    |> Atom.to_charlist()
    |> Enum.chunk_by(& &1)
    |> Enum.sort()
  end

  @doc false
  # The options TR35 applies to the pattern a semantic skeleton matched
  # rather than to the skeleton: an exact hour cycle's symbol and column
  # alignment's padding. Every formatter that resolves a semantic skeleton
  # passes the pattern through here, so no path applies one and not the
  # other.
  @spec apply_pattern_variations(String.t(), t() | term()) :: String.t()
  def apply_pattern_variations(pattern, %__MODULE__{} = skeleton) when is_binary(pattern) do
    pattern
    |> apply_hour_cycle(skeleton)
    |> apply_alignment(skeleton)
  end

  def apply_pattern_variations(pattern, _skeleton), do: pattern

  @doc false
  # TR35 §Hour Cycle Pattern Variations. Standard skeletons carry only the
  # canonical `h` and `H`, and the matched `dateFormatItem` encodes whichever
  # cycle the locale prefers — `ja` writes `aK:mm:ss` for `hms`. So a caller
  # asking for an exact cycle cannot get it from skeleton choice alone; the
  # symbol has to be substituted into the pattern after matching. The clock
  # preferences deliberately do not substitute: they take the locale's
  # pattern as it stands.
  @spec apply_hour_cycle(String.t(), t() | term()) :: String.t()
  def apply_hour_cycle(pattern, %__MODULE__{hour_cycle: cycle}) when is_binary(pattern) do
    case Map.fetch(@exact_hour_cycles, cycle) do
      {:ok, symbol} -> substitute_hour_symbol(pattern, symbol)
      :error -> pattern
    end
  end

  def apply_hour_cycle(pattern, _skeleton), do: pattern

  # Each hour character is replaced individually so the pattern keeps the
  # width it asked for: `hh` becomes `HH`, not `H`. Characters inside a
  # quoted literal are left alone.
  defp substitute_hour_symbol(pattern, symbol) do
    pattern
    |> String.graphemes()
    |> Enum.map_reduce(false, fn
      "'", quoted -> {"'", not quoted}
      grapheme, false when grapheme in ["h", "H", "K", "k"] -> {symbol, false}
      grapheme, quoted -> {grapheme, quoted}
    end)
    |> elem(0)
    |> Enum.join()
  end

  # TR35 §Alignment: `:column` renders the numeric fields it affects with at
  # least two digits. As ICU4X does, a month, day or hour written with one
  # letter is widened to two, which pads a number and leaves a spelled-out
  # month (`MMM`) as it is; the year is not touched. Quoted literal text
  # keeps its letters.
  defp apply_alignment(pattern, %__MODULE__{alignment: :column}) do
    pattern
    |> String.graphemes()
    |> Enum.chunk_by(& &1)
    |> Enum.map_reduce(false, fn
      ["'" | _rest] = quotes, quoted -> {quotes, quoted_after(quotes, quoted)}
      [symbol], false when symbol in @column_padded_symbols -> {[symbol, symbol], false}
      run, quoted -> {run, quoted}
    end)
    |> elem(0)
    |> IO.iodata_to_binary()
  end

  defp apply_alignment(pattern, _skeleton), do: pattern

  # Each quote opens or closes quoted text, and a doubled quote is a literal
  # quote that leaves the state as it was.
  defp quoted_after(quotes, quoted) do
    if rem(length(quotes), 2) == 1, do: not quoted, else: quoted
  end

  # ── Date widths ─────────────────────────────────────────────

  # TR35 takes the year, month and day from the locale's date format at the
  # requested length — Localize keeps each format's skeleton as its
  # `date_formats` — so `de`'s numeric medium date gives `yMMdd` where `en`
  # gives `yMMMd`, and a calendar whose years run by era brings the era with
  # its year. A skeleton with none of those fields needs no data.
  defp date_widths(%{fields: fields, length: length}, locale_id, calendar_type) do
    if Enum.any?(fields, &(&1 in [:year, :month, :day])) do
      with {:ok, formats} <- Localize.DateTime.Format.date_formats(locale_id, calendar_type) do
        {:ok, split_date_skeleton(Map.get(formats, length))}
      end
    else
      {:ok, %{}}
    end
  end

  defp split_date_skeleton(skeleton) when is_atom(skeleton) and not is_nil(skeleton) do
    skeleton
    |> Atom.to_charlist()
    |> Enum.chunk_by(& &1)
    |> Enum.reduce(%{}, fn [symbol | _rest] = run, widths ->
      case date_symbol_field(symbol) do
        nil -> widths
        field -> Map.update(widths, field, List.to_string(run), &(&1 <> List.to_string(run)))
      end
    end)
  end

  defp split_date_skeleton(_skeleton), do: %{}

  defp date_symbol_field(symbol) when symbol in @year_symbols, do: :year
  defp date_symbol_field(symbol) when symbol in @month_symbols, do: :month
  defp date_symbol_field(?d), do: :day
  defp date_symbol_field(_symbol), do: nil

  # ── Field patterns ──────────────────────────────────────────

  defp field_pattern(:year, skeleton, widths, _value) do
    widths
    |> Map.get(:year, "y")
    |> year_pattern(skeleton.year_style)
  end

  # A month asked for on its own is the standalone form, which TR35 fixes by
  # length rather than taking from the date format.
  defp field_pattern(:month, %{fields: [:month], length: length}, _widths, _value) do
    case length do
      :long -> "LLLL"
      :medium -> "LLL"
      :short -> "L"
    end
  end

  defp field_pattern(:month, %{length: length}, widths, _value) do
    Map.get_lazy(widths, :month, fn ->
      case length do
        :long -> "MMMM"
        :medium -> "MMM"
        :short -> "M"
      end
    end)
  end

  defp field_pattern(:day, _skeleton, widths, _value), do: Map.get(widths, :day, "d")

  # A weekday on its own is narrow at short length; beside a date it keeps
  # the abbreviation, since the date already says which day it is.
  defp field_pattern(:weekday, %{length: :long}, _widths, _value), do: "EEEE"

  defp field_pattern(:weekday, %{fields: [:weekday], length: :short}, _widths, _value),
    do: "EEEEE"

  defp field_pattern(:weekday, _skeleton, _widths, _value), do: "EEE"

  defp field_pattern(:time, skeleton, _widths, value) do
    hour_symbol(skeleton.hour_cycle) <> precision_pattern(skeleton.time_precision, value)
  end

  defp field_pattern(:zone, %{zone_style: :location}, _widths, _value), do: "VVVV"

  defp field_pattern(:zone, %{zone_style: style} = skeleton, _widths, _value) do
    zone_symbol(style, zone_form(skeleton))
  end

  # TR35 §Year Style Skeleton Variations: `:auto` keeps the locale's year,
  # `:full` restores a truncated one and `:with_era` adds an era if the
  # locale's format has none.
  defp year_pattern(year, :auto), do: year
  defp year_pattern(year, :full), do: String.replace(year, "yy", "y")

  defp year_pattern(year, :with_era) do
    year = String.replace(year, "yy", "y")
    if String.contains?(year, "G"), do: year, else: "G" <> year
  end

  # `j` asks for the locale's own hour cycle, which is what a semantic
  # request means: the caller wants a time, not a 24-hour clock. `h` and `H`
  # force one when the caller has a reason to.
  defp hour_symbol(cycle) when cycle in @twelve_hour_cycles, do: "h"
  defp hour_symbol(cycle) when cycle in @twenty_four_hour_cycles, do: "H"
  defp hour_symbol(_cycle), do: "j"

  # TR35 §Time Precision Skeleton Variations.
  defp precision_pattern(:hour, _value), do: ""
  defp precision_pattern(:minute, _value), do: "m"
  defp precision_pattern(:minute_optional, %{minute: 0}), do: ""
  defp precision_pattern(:minute_optional, _value), do: "m"
  defp precision_pattern(:second, _value), do: "ms"

  defp precision_pattern({:fractional_second, digits}, _value),
    do: "ms" <> String.duplicate("S", digits)

  # TR35's table gives a zone on its own the long form, except at short
  # length, and a zone beside other fields the short one; an offset is
  # always short. `:zone_length` overrides the table.
  defp zone_form(%{zone_length: form}) when form in [:short, :long], do: form
  defp zone_form(%{zone_style: :offset}), do: :short
  defp zone_form(%{fields: [:zone], length: :short}), do: :short
  defp zone_form(%{fields: [:zone]}), do: :long
  defp zone_form(_skeleton), do: :short

  defp zone_symbol(:specific, :short), do: "z"
  defp zone_symbol(:specific, :long), do: "zzzz"
  defp zone_symbol(:generic, :short), do: "v"
  defp zone_symbol(:generic, :long), do: "vvvv"
  defp zone_symbol(:offset, :short), do: "O"
  defp zone_symbol(:offset, :long), do: "OOOO"

  # ── Validation ──────────────────────────────────────────────

  # `given` is the code or list as the caller wrote it, for the error.
  defp build(fields, options, given) do
    with {:ok, field_set} <- validate_field_set(fields, given),
         {:ok, skeleton} <- validate_options(field_set, options),
         :ok <- validate_option_fields(options, field_set, given) do
      {:ok, skeleton}
    end
  end

  # A struct built by hand has not been through `new/2`, so the formatters
  # check it here: its fields must be a TR35 field set and its option values
  # ones `new/2` accepts. A struct holds every option, so which were given
  # cannot be told, and the fields each applies to go unchecked.
  defp validate_skeleton(%__MODULE__{fields: fields} = skeleton) when is_list(fields) do
    options = skeleton |> Map.from_struct() |> Map.delete(:fields) |> Map.to_list()

    with {:ok, field_set} <- validate_field_set(fields, fields) do
      validate_options(field_set, options)
    end
  end

  defp validate_skeleton(%__MODULE__{fields: fields}) do
    {:error,
     Localize.InvalidValueError.exception(
       value: fields,
       expected: "a list of fields",
       context: "Localize.DateTime.SemanticSkeleton"
     )}
  end

  # TR35's conformance rules make a field set it does not define an error.
  # The fields form a set, so each may appear once and their order does not
  # matter; they are kept in the order of `@codes`.
  defp validate_field_set(fields, given) do
    with {:ok, fields} <- validate_fields(fields) do
      field_set = Enum.sort_by(fields, &Map.fetch!(@field_order, &1))

      if field_set in @field_sets do
        {:ok, field_set}
      else
        {:error,
         Localize.InvalidValueError.exception(
           value: given,
           expected: :field_set,
           allowed_values: @field_set_codes,
           context: "Localize.DateTime.SemanticSkeleton"
         )}
      end
    end
  end

  defp validate_options(field_set, options) do
    with {:ok, length} <- validate(options, :length, @lengths, :medium),
         {:ok, year_style} <- validate(options, :year_style, @year_styles, :auto),
         {:ok, zone_style} <- validate(options, :zone_style, @zone_styles, :specific),
         {:ok, zone_length} <- validate(options, :zone_length, @zone_lengths, :auto),
         {:ok, hour_cycle} <- validate(options, :hour_cycle, @hour_cycles, :auto),
         {:ok, time_precision} <- validate_time_precision(options),
         {:ok, alignment} <- validate(options, :alignment, @alignments, :inline) do
      {:ok,
       %__MODULE__{
         fields: field_set,
         length: length,
         year_style: year_style,
         zone_style: zone_style,
         zone_length: zone_length,
         hour_cycle: hour_cycle,
         time_precision: time_precision,
         alignment: alignment
       }}
    end
  end

  # TR35's conformance rules make an option given for a field set holding
  # none of the fields it applies to an error, whatever its value.
  defp validate_option_fields(options, field_set, given) do
    Enum.find_value(@option_fields, :ok, fn {option, {applies_to, description}} ->
      if Keyword.has_key?(options, option) and not Enum.any?(applies_to, &(&1 in field_set)) do
        {:error,
         Localize.InvalidValueError.exception(
           value: given,
           expected: "a field set with #{description}",
           context: "Localize.DateTime.SemanticSkeleton #{inspect(option)}"
         )}
      end
    end)
  end

  defp parse_code(code) do
    code
    |> String.to_charlist()
    |> Enum.reduce_while({:ok, []}, fn char, {:ok, fields} ->
      case Map.fetch(@codes, char) do
        {:ok, field} ->
          {:cont, {:ok, [field | fields]}}

        :error ->
          {:halt,
           {:error,
            Localize.InvalidValueError.exception(
              value: <<char::utf8>>,
              expected: "one of Y, M, D, E, T, Z",
              context: "Localize.DateTime.SemanticSkeleton"
            )}}
      end
    end)
    |> case do
      {:ok, fields} -> {:ok, Enum.reverse(fields)}
      error -> error
    end
  end

  # A binary that is not UTF-8 names no fields, and reading it as code points
  # would raise.
  defp validate_code(code) do
    if String.valid?(code) do
      :ok
    else
      {:error,
       Localize.InvalidValueError.exception(
         value: code,
         expected: "a field code string such as \"YMDE\"",
         context: "Localize.DateTime.SemanticSkeleton"
       )}
    end
  end

  defp validate_fields(fields) do
    known = Map.values(@codes)

    case Enum.reject(fields, &(&1 in known)) do
      [] ->
        {:ok, fields}

      [unknown | _rest] ->
        {:error,
         Localize.InvalidValueError.exception(
           value: unknown,
           expected: "one of #{inspect(known)}",
           context: "Localize.DateTime.SemanticSkeleton"
         )}
    end
  end

  defp validate(options, key, allowed, default) do
    value = Keyword.get(options, key, default)

    if value in allowed do
      {:ok, value}
    else
      {:error,
       Localize.InvalidValueError.exception(
         value: value,
         expected: "one of #{inspect(allowed)}",
         context: "Localize.DateTime.SemanticSkeleton #{inspect(key)}"
       )}
    end
  end

  defp validate_time_precision(options) do
    case Keyword.get(options, :time_precision, :second) do
      precision when precision in @time_precisions ->
        {:ok, precision}

      {:fractional_second, digits} = precision when digits in 1..9 ->
        {:ok, precision}

      other ->
        {:error,
         Localize.InvalidValueError.exception(
           value: other,
           expected: "one of #{inspect(@time_precisions)} or {:fractional_second, 1..9}",
           context: "Localize.DateTime.SemanticSkeleton :time_precision"
         )}
    end
  end
end
