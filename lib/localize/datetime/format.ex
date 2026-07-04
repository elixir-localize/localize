defmodule Localize.DateTime.Format do
  @moduledoc false

  # Provides access to CLDR date, time, and datetime format
  # patterns for a given locale and calendar type.
  #
  # All data is loaded at runtime via `Localize.Locale.get/2`.

  @default_calendar_type :gregorian
  @standard_formats [:short, :medium, :long, :full]

  # CLDR's `alt` attribute names two independent axes for date/time
  # patterns: `:variant` / `:standard` (locale-preferred vs ISO-style)
  # and `:unicode` / `:ascii` (NBSP and curly quotes vs ASCII-only).
  # `:prefer` accepts an atom or list of atoms naming the alts the
  # caller wants. The resolver picks the first match per axis,
  # falling back to these defaults when no preference applies.
  @default_prefer [:standard, :unicode]

  # # standard_formats/0
  #
  # Returns the list of standard format names.
  #
  # ### Returns
  #
  # * `[:short, :medium, :long, :full]`
  #
  @spec standard_formats() :: [:short | :medium | :long | :full, ...]
  def standard_formats, do: @standard_formats

  # # date_formats/2
  #
  # Returns the standard date format skeletons for a locale.
  #
  # ### Arguments
  #
  # * `locale_id` is a locale identifier atom.
  #
  # * `calendar_type` is a CLDR calendar type atom.
  #
  # ### Returns
  #
  # * `{:ok, %{short: skeleton, medium: skeleton, ...}}`
  #
  # * `{:error, exception}`
  #
  @spec date_formats(atom(), atom()) :: {:ok, map()} | {:error, Exception.t()}
  def date_formats(locale_id, calendar_type \\ @default_calendar_type) do
    Localize.Locale.get(locale_id, [:dates, :calendars, calendar_type, :date_formats])
  end

  # # time_formats/2
  #
  # Returns the standard time format skeletons for a locale.
  #
  @spec time_formats(atom(), atom()) :: {:ok, map()} | {:error, Exception.t()}
  def time_formats(locale_id, calendar_type \\ @default_calendar_type) do
    Localize.Locale.get(locale_id, [:dates, :calendars, calendar_type, :time_formats])
  end

  # # date_time_formats/2
  #
  # Returns the datetime wrapper patterns for a locale.
  # These are patterns like `"{1}, {0}"` that combine
  # date and time parts.
  #
  @spec date_time_formats(atom(), atom()) :: {:ok, map()} | {:error, Exception.t()}
  def date_time_formats(locale_id, calendar_type \\ @default_calendar_type) do
    Localize.Locale.get(locale_id, [:dates, :calendars, calendar_type, :date_time_formats])
  end

  # # date_time_at_formats/2
  #
  # Returns the "at" joining patterns for a locale.
  #
  @spec date_time_at_formats(atom(), atom()) :: {:ok, map()} | {:error, Exception.t()}
  def date_time_at_formats(locale_id, calendar_type \\ @default_calendar_type) do
    Localize.Locale.get(locale_id, [:dates, :calendars, calendar_type, :date_time_at_formats])
  end

  # # available_formats/2
  #
  # Returns the skeleton-to-pattern map for a locale.
  # Keys are format skeleton atoms (e.g., `:yMMMd`),
  # values are format pattern strings (e.g., `"MMM d, y"`).
  #
  @spec available_formats(atom(), atom()) :: {:ok, map()} | {:error, Exception.t()}
  def available_formats(locale_id, calendar_type \\ @default_calendar_type) do
    Localize.Locale.get(locale_id, [:dates, :calendars, calendar_type, :available_formats])
  end

  # # interval_formats/2
  #
  # Returns the interval format patterns for a locale.
  #
  @spec interval_formats(atom(), atom()) :: {:ok, map()} | {:error, Exception.t()}
  def interval_formats(locale_id, calendar_type \\ @default_calendar_type) do
    Localize.Locale.get(locale_id, [:dates, :calendars, calendar_type, :interval_formats])
  end

  # # resolve_standard_format/3
  #
  # Resolves a standard format name to a pattern string.
  #
  # Standard formats (`:short`, `:medium`, `:long`, `:full`)
  # first resolve to a skeleton atom via the format map,
  # then the skeleton resolves to a pattern string via
  # available_formats.
  #
  # ### Arguments
  #
  # * `format_type` is `:date`, `:time`, or `:date_time`.
  #
  # * `format_name` is a standard format atom or skeleton atom.
  #
  # * `locale_id` is a locale identifier atom.
  #
  # * `calendar_type` is a CLDR calendar type atom.
  #
  # * `options` is a keyword list. `:prefer` controls
  #   unicode vs ascii preference for time formats.
  #
  # ### Returns
  #
  # * `{:ok, pattern_string}` or `{:error, exception}`.
  #
  @spec resolve_format(
          :date | :time | :date_time,
          atom() | String.t(),
          atom(),
          atom(),
          Keyword.t()
        ) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def resolve_format(
        format_type,
        format_name,
        locale_id,
        calendar_type \\ @default_calendar_type,
        options \\ []
      )

  def resolve_format(_format_type, format_string, _locale_id, _calendar_type, _options)
      when is_binary(format_string) do
    {:ok, format_string}
  end

  def resolve_format(format_type, format_name, locale_id, calendar_type, options)
      when is_atom(format_name) do
    with {:ok, formats_map} <- formats_for_type(format_type, locale_id, calendar_type),
         {:ok, available} <- available_formats(locale_id, calendar_type) do
      # Standard format names resolve to skeleton atoms first
      skeleton =
        if format_name in @standard_formats do
          Map.get(formats_map, format_name)
        else
          format_name
        end

      case Map.get(available, skeleton) do
        nil ->
          {:error,
           Localize.DateTimeUnresolvedFormatError.exception(
             format: format_name,
             locale: locale_id
           )}

        %{} = variant_map ->
          variant_map
          |> resolve_variant(options)
          |> variant_pattern_result(format_name, locale_id)

        pattern when is_binary(pattern) ->
          {:ok, pattern}
      end
    end
  end

  defp variant_pattern_result(nil, format_name, locale_id) do
    {:error,
     Localize.DateTimeUnresolvedFormatError.exception(
       format: format_name,
       locale: locale_id
     )}
  end

  defp variant_pattern_result(pattern, _format_name, _locale_id) do
    {:ok, pattern}
  end

  @doc """
  Extracts the CLDR `number_system` overrides for a resolved
  `(format_type, format_name, locale, calendar)` tuple.

  Some CLDR date patterns carry per-field number-system overrides
  alongside the pattern string (e.g. Japanese imperial year via
  `jpanyear`, Hebrew dates via `hebr`). The variant map shape is
  `%{format: "<pattern>", number_system: %{"all" | "y" | "M" |
  "d" | ... => ns_atom}}`. This function returns just that
  per-field map — `%{}` when the format has no overrides or
  isn't a variant of that shape.

  ### Returns

  * A map `%{String.t() => atom()}` keyed by CLDR field symbol
    ("y", "M", "d", …) or `"all"` meaning every numeric field.

  ### Examples

      iex> Localize.DateTime.Format.number_system_overrides(:date, :medium, :"ja-JP", :japanese)
      %{"y" => :jpanyear}

      iex> Localize.DateTime.Format.number_system_overrides(:date, :medium, :en, :gregorian)
      %{}

  """
  @spec number_system_overrides(
          :date | :time | :date_time,
          atom() | String.t(),
          atom(),
          atom()
        ) :: %{String.t() => atom()}
  def number_system_overrides(format_type, format_name, locale_id, calendar_type)
      when is_atom(format_name) do
    with {:ok, formats_map} <- formats_for_type(format_type, locale_id, calendar_type),
         {:ok, available} <- available_formats(locale_id, calendar_type) do
      skeleton =
        if format_name in @standard_formats do
          Map.get(formats_map, format_name)
        else
          format_name
        end

      case Map.get(available, skeleton) do
        %{number_system: %{} = overrides} -> overrides
        _ -> %{}
      end
    else
      _ -> %{}
    end
  end

  def number_system_overrides(_format_type, _format_name, _locale_id, _calendar_type), do: %{}

  # # resolve_variant/2
  #
  # Picks one pattern from a CLDR `alt`-keyed variant map.
  #
  # CLDR puts several independent kinds of alternates under the
  # same `alt` attribute, so the data we receive can be keyed by:
  #
  #   * `:variant` / `:standard` — locale-preferred pattern vs
  #     ISO-style pattern (e.g. en-CA's `:yyMd` → `"d/M/yy"` vs
  #     `"y-MM-dd"`).
  #
  #   * `:unicode` / `:ascii` — patterns that use Unicode quote /
  #     space characters vs ASCII-only ones (mostly time formats).
  #
  #   * `:zero` / `:one` / `:two` / `:few` / `:many` / `:other` —
  #     plural-keyed patterns (e.g. `MMMMW` → "week W of MMMM").
  #     Without a numeric value at this stage we fall back to
  #     `:other`, which CLDR guarantees to be present.
  #
  # `options[:prefer]` is an atom or list of atoms naming the
  # alts the caller wants, in priority order — e.g.
  # `prefer: :ascii`, `prefer: [:variant, :ascii]`. For each axis
  # present in the variant map the first matching atom is used;
  # if no preference matches that axis, falls back to the
  # built-in default (`:standard` for variant axis, `:unicode` for
  # unicode/ascii axis, `:other` for plural axis).
  @doc false
  @spec resolve_variant(map() | binary() | term(), Keyword.t()) :: binary() | nil
  def resolve_variant(value, options \\ [])

  def resolve_variant(pattern, _options) when is_binary(pattern), do: pattern

  def resolve_variant(%{} = variant_map, options) do
    prefer = options |> Keyword.get(:prefer, @default_prefer) |> List.wrap()

    cond do
      Map.has_key?(variant_map, :variant) or Map.has_key?(variant_map, :standard) ->
        pick(variant_map, prefer, [:standard, :variant])

      Map.has_key?(variant_map, :unicode) or Map.has_key?(variant_map, :ascii) ->
        pick(variant_map, prefer, [:unicode, :ascii])

      # CLDR `{format: "<pattern>", number_system: %{...}}`
      # shape — the pattern is the format string; the
      # `:number_system` companion tells the formatter which
      # digit set to render numeric fields with (e.g.
      # `jpanyear` for Japanese imperial year). We surface
      # the pattern here and rely on the formatter to read
      # the number_system separately when it needs to.
      Map.has_key?(variant_map, :format) ->
        Map.get(variant_map, :format)

      Map.has_key?(variant_map, :other) ->
        Map.get(variant_map, :other)

      true ->
        nil
    end
  end

  def resolve_variant(_other, _options), do: nil

  # Picks the first key from `prefer` that names a value in
  # `variant_map`; if none of the user's preferences apply to
  # this axis, walks the axis's `defaults` list to find a value.
  defp pick(variant_map, prefer, defaults) do
    Enum.find_value(prefer ++ defaults, fn key -> Map.get(variant_map, key) end)
  end

  defp formats_for_type(:date, locale_id, calendar_type),
    do: date_formats(locale_id, calendar_type)

  defp formats_for_type(:time, locale_id, calendar_type),
    do: time_formats(locale_id, calendar_type)

  defp formats_for_type(:date_time, locale_id, calendar_type),
    do: date_time_formats(locale_id, calendar_type)
end
