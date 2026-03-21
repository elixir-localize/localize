defmodule Localize.DateTime.Format do
  @moduledoc false

  # Provides access to CLDR date, time, and datetime format
  # patterns for a given locale and calendar type.
  #
  # All data is loaded at runtime via `Localize.Locale.get/2`.

  @default_calendar_type :gregorian
  @standard_formats [:short, :medium, :long, :full]
  @default_prefer :unicode

  # # standard_formats/0
  #
  # Returns the list of standard format names.
  #
  # ### Returns
  #
  # * `[:short, :medium, :long, :full]`
  #
  @spec standard_formats() :: [atom()]
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
    prefer = Keyword.get(options, :prefer, @default_prefer)

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
          # Time formats may have unicode/ascii variants
          pattern = Map.get(variant_map, prefer) || Map.get(variant_map, :unicode)
          {:ok, pattern}

        pattern when is_binary(pattern) ->
          {:ok, pattern}
      end
    end
  end

  defp formats_for_type(:date, locale_id, calendar_type),
    do: date_formats(locale_id, calendar_type)

  defp formats_for_type(:time, locale_id, calendar_type),
    do: time_formats(locale_id, calendar_type)

  defp formats_for_type(:date_time, locale_id, calendar_type),
    do: date_time_formats(locale_id, calendar_type)
end
