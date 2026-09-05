defmodule Localize.DateTime.SemanticSkeleton do
  @moduledoc """
  TR35 semantic skeletons: asking for a date or time by *meaning* rather
  than by which fields to render.

  A classical skeleton such as `:yMMMd` is an instruction — year, abbreviated
  month, day. A semantic skeleton is a request: "year, month, day and
  weekday, at medium length", written `YMDE`. The library then chooses the
  fields, and a locale is free to choose differently.

  CLDR ships no data for this. `semanticSkeleton` appears in exactly one file
  in the whole repository — the datetime conformance data — and that file
  gives the mapping directly, pairing each semantic skeleton with the
  classical skeleton it resolves to. So this module is a resolver over data
  Localize already has, not a new data source.

  ## Field codes

  The skeleton code names the fields wanted, in this order:

  * `Y` — year

  * `M` — month

  * `D` — day of the month

  * `E` — day of the week

  * `T` — time

  * `Z` — time zone

  So `YMD` is a plain date, `YMDE` adds the weekday, `T` is a time on its
  own, and `MDTZ` is a month, day, time and zone together.

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

  defstruct fields: [],
            length: :medium,
            year_style: :auto,
            zone_style: :specific,
            hour_cycle: :auto,
            alignment: :auto

  @type field :: :year | :month | :day | :weekday | :time | :zone

  @type t :: %__MODULE__{
          fields: [field()],
          length: :short | :medium | :long,
          year_style: :auto | :full | :with_era,
          zone_style: :specific | :generic | :location | :offset,
          hour_cycle: :auto | :h12 | :h23,
          alignment: :auto | :column
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
  @hour_cycles [:auto, :h12, :h23]
  @alignments [:auto, :column]

  @doc """
  Builds a semantic skeleton.

  ### Arguments

  * `code` is a string of field codes such as `"YMDE"` or `"MDTZ"`, or a
    list of field atoms such as `[:year, :month, :day]`.

  * `options` is a keyword list.

  ### Options

  * `:length` is `:short`, `:medium` (the default) or `:long`. It selects
    how much of each field to show — `:short` gives a numeric month, `:long`
    the full name.

  * `:year_style` is `:auto` (the default), `:full` or `:with_era`. `:auto`
    abbreviates the year where the locale does, and shows an era only for
    calendars that need one to be unambiguous.

  * `:zone_style` is `:specific` (the default), `:generic`, `:location` or
    `:offset`. Only consulted when the skeleton carries `Z`.

  * `:hour_cycle` is `:auto` (the default), `:h12` or `:h23`. `:auto` uses
    the locale's own cycle, which is what a semantic request usually means;
    the other two force a 12- or 24-hour clock.

  * `:alignment` is `:auto` (the default) or `:column`, the latter asking
    for fields padded to a fixed width for tabular display.

  ### Returns

  * `{:ok, skeleton}`.

  * `{:error, exception}` if a field code or option value is unknown.

  ### Examples

      iex> {:ok, skeleton} = Localize.DateTime.SemanticSkeleton.new("YMDE")
      iex> skeleton.fields
      [:year, :month, :day, :weekday]

      iex> Localize.DateTime.SemanticSkeleton.new("YMDQ")
      {:error, %Localize.InvalidValueError{value: "Q", expected: "one of Y, M, D, E, T, Z", context: "Localize.DateTime.SemanticSkeleton"}}

  """
  @spec new(String.t() | [field()], Keyword.t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(code, options \\ [])

  def new(code, options) when is_binary(code) do
    with {:ok, fields} <- parse_code(code) do
      new(fields, options)
    end
  end

  def new(fields, options) when is_list(fields) do
    with {:ok, fields} <- validate_fields(fields),
         {:ok, length} <- validate(options, :length, @lengths, :medium),
         {:ok, year_style} <- validate(options, :year_style, @year_styles, :auto),
         {:ok, zone_style} <- validate(options, :zone_style, @zone_styles, :specific),
         {:ok, hour_cycle} <- validate(options, :hour_cycle, @hour_cycles, :auto),
         {:ok, alignment} <- validate(options, :alignment, @alignments, :auto) do
      {:ok,
       %__MODULE__{
         fields: fields,
         length: length,
         year_style: year_style,
         zone_style: zone_style,
         hour_cycle: hour_cycle,
         alignment: alignment
       }}
    end
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

  * `Localize.InvalidValueError` if a field code or option value is unknown.

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

  This is the mapping the CLDR conformance data records: `YMDE` at short
  length is `yyMdEEE`, and with an era `GyMdEEE`. The result is an ordinary
  skeleton atom, resolved from there by the machinery that already handles
  `format: :yMMMd`.

  ### Arguments

  * `skeleton` is a `t:t/0`.

  * `calendar` is a CLDR calendar name atom such as `:gregorian`. Calendars
    other than `:gregorian` carry an era by default, since a year alone does
    not identify a date in them.

  ### Returns

  * `{:ok, atom}` — the classical skeleton.

  * `{:error, exception}` if the skeleton names no fields.

  ### Examples

      iex> skeleton = Localize.DateTime.SemanticSkeleton.semantic("YMDE", length: :short)
      iex> Localize.DateTime.SemanticSkeleton.to_classical_skeleton(skeleton, :gregorian)
      {:ok, :yyMdEEE}

      iex> skeleton = Localize.DateTime.SemanticSkeleton.semantic("YMDE", length: :long)
      iex> Localize.DateTime.SemanticSkeleton.to_classical_skeleton(skeleton, :gregorian)
      {:ok, :yMMMMdEEEE}

  """
  @spec to_classical_skeleton(t(), atom()) :: {:ok, atom()} | {:error, Exception.t()}
  def to_classical_skeleton(skeleton, calendar \\ :gregorian)

  def to_classical_skeleton(%__MODULE__{fields: []} = skeleton, _calendar) do
    {:error,
     Localize.InvalidValueError.exception(
       value: skeleton,
       expected: "a skeleton naming at least one field",
       context: "Localize.DateTime.SemanticSkeleton.to_classical_skeleton/2"
     )}
  end

  def to_classical_skeleton(%__MODULE__{} = skeleton, calendar) do
    pattern =
      skeleton.fields
      |> Enum.map_join(&field_pattern(&1, skeleton, calendar))
      |> then(&(era_width(skeleton, calendar) <> &1))

    {:ok, String.to_atom(pattern)}
  end

  # ── Field patterns ──────────────────────────────────────────

  # The widths come from the conformance data rather than from a reading of
  # the prose: `YMDE` short is `yyMdEEE`, medium `yMMMdEEE`, long
  # `yMMMMdEEEE`, and `M` alone at long is the standalone `LLLL`.
  #
  # A two-digit year is only unambiguous when nothing else pins the date
  # down, so it appears at short length and only where no era is shown.
  defp field_pattern(:year, %{length: :short} = skeleton, calendar) do
    if era_prefix(skeleton, calendar) == "", do: "yy", else: "y"
  end

  defp field_pattern(:year, _skeleton, _calendar), do: "y"

  defp field_pattern(:month, %{fields: [:month], length: :long}, _calendar), do: "LLLL"
  defp field_pattern(:month, %{length: :short}, _calendar), do: "M"
  defp field_pattern(:month, %{length: :medium}, _calendar), do: "MMM"

  # Japanese era names are long enough that a full month name alongside one
  # makes the result unwieldy, so CLDR abbreviates the month at long length
  # for that calendar alone.
  defp field_pattern(:month, %{length: :long}, :japanese), do: "MMM"
  defp field_pattern(:month, %{length: :long}, _calendar), do: "MMMM"

  defp field_pattern(:day, _skeleton, _calendar), do: "d"

  defp field_pattern(:weekday, %{length: :long}, _calendar), do: "EEEE"
  defp field_pattern(:weekday, _skeleton, _calendar), do: "EEE"

  # `j` asks for the locale's own hour cycle, which is what a semantic
  # request means: the caller wants a time, not a 24-hour clock. `h` and `H`
  # force one when the caller has a reason to.
  defp field_pattern(:time, %{hour_cycle: :h12}, _calendar), do: "hms"
  defp field_pattern(:time, %{hour_cycle: :h23}, _calendar), do: "Hms"
  defp field_pattern(:time, _skeleton, _calendar), do: "jms"

  # Zone width follows the company it keeps, not the requested length: a zone
  # asked for on its own is the whole answer and gets the full name, while a
  # zone trailing a date and time is a qualifier and gets the short one.
  # Location and offset styles have a single form either way.
  defp field_pattern(:zone, %{zone_style: :location}, _calendar), do: "VVVV"
  defp field_pattern(:zone, %{zone_style: :offset}, _calendar), do: "O"

  defp field_pattern(:zone, %{zone_style: style, fields: [:zone]}, _calendar) do
    case style do
      :specific -> "zzzz"
      :generic -> "vvvv"
    end
  end

  defp field_pattern(:zone, %{zone_style: style}, _calendar) do
    case style do
      :specific -> "z"
      :generic -> "v"
    end
  end

  # Calendars whose year count restarts — Japanese reigns, the Islamic
  # calendars — need an era to identify a year at all, so they always carry
  # one, narrow at short length where space is tight. Gregorian and Buddhist
  # years run continuously and show an era only when asked.
  @continuous_year_calendars [:gregorian, :buddhist]

  # A narrow era ("R" rather than "Reiwa") at short length, where the whole
  # point is brevity — but only for the calendars that must show one.
  defp era_width(skeleton, calendar) do
    case era_prefix(skeleton, calendar) do
      "" -> ""
      "G" when calendar not in @continuous_year_calendars and skeleton.length == :short -> "GGGGG"
      era -> era
    end
  end

  defp era_prefix(%{fields: fields} = skeleton, calendar) do
    if :year in fields, do: year_era_prefix(skeleton, calendar), else: ""
  end

  defp year_era_prefix(_skeleton, calendar) when calendar not in @continuous_year_calendars do
    "G"
  end

  defp year_era_prefix(%{year_style: :with_era}, _calendar), do: "G"
  defp year_era_prefix(_skeleton, _calendar), do: ""

  # ── Validation ──────────────────────────────────────────────

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
end
