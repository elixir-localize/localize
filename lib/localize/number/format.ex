defmodule Localize.Number.Format do
  @moduledoc """
  Functions to manage the collection of number format patterns
  defined in CLDR.

  Number patterns affect how numbers are interpreted in a localized
  context. A format pattern such as `"#,##0.###"` defines the decimal
  and grouping separators, zero-padding, and digit positions. The
  actual separator characters are determined by the locale's number
  symbols.

  Format data is retrieved at runtime from locale data via the
  configured locale provider.

  """

  alias Localize.Number.System

  @short_format_styles [:decimal_long, :decimal_short, :currency_short, :currency_long]

  @format_styles [
                   :standard,
                   :currency,
                   :accounting,
                   :scientific,
                   :engineering,
                   :percent,
                   :accounting_alpha_next_to_number,
                   :accounting_no_symbol,
                   :currency_alpha_next_to_number,
                   :currency_no_symbol
                 ] ++ @short_format_styles

  defstruct @format_styles ++ [:currency_spacing, :other, :rational]

  @behaviour Access

  @type format :: String.t()

  @type t :: %__MODULE__{}

  @impl Access
  def fetch(struct, key), do: Map.fetch(struct, key)

  @impl Access
  def get_and_update(struct, key, function) do
    current = Map.get(struct, key)

    case function.(current) do
      {get, update} -> {get, Map.put(struct, key, update)}
      :pop -> {current, Map.delete(struct, key)}
    end
  end

  @impl Access
  def pop(struct, key) do
    {Map.get(struct, key), Map.delete(struct, key)}
  end

  @reject_styles [:__struct__, :currency_spacing, :other, :rational]
  @isnt_really_a_short_format [:currency_long]
  @short_formats MapSet.new(@short_format_styles -- @isnt_really_a_short_format)

  @doc """
  Returns the short format style names.

  ### Returns

  * A list of atoms: `[:decimal_long, :decimal_short, :currency_short, :currency_long]`.

  ### Examples

      iex> Localize.Number.Format.short_format_styles()
      [:decimal_long, :decimal_short, :currency_short, :currency_long]

  """
  @spec short_format_styles() :: [
          :decimal_long | :decimal_short | :currency_short | :currency_long,
          ...
        ]
  def short_format_styles do
    @short_format_styles
  end

  @doc """
  Returns all number formats defined for a locale, keyed by
  number system.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0` struct.

  ### Returns

  * `{:ok, formats_map}` where `formats_map` is a map of
    `%{system_name => Localize.Number.Format.t()}`.

  * `{:error, exception}` if the locale data cannot be loaded.

  ### Examples

      iex> {:ok, formats} = Localize.Number.Format.all_formats_for(:en)
      iex> Map.has_key?(formats, :latn)
      true

  """
  @spec all_formats_for(Localize.LanguageTag.t() | atom() | String.t()) ::
          {:ok, map()} | {:error, Exception.t()}
  def all_formats_for(locale) do
    with {:ok, locale_id} <- cldr_locale_id_from(locale) do
      Localize.Locale.get(locale_id, [:number_formats])
    end
  end

  @doc """
  Same as `all_formats_for/1` but raises on error.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0` struct.

  ### Returns

  * A map of formats keyed by number system.

  ### Raises

  * Raises an exception if the locale data cannot be loaded.

  ### Examples

      iex> formats = Localize.Number.Format.all_formats_for!(:en)
      iex> formats[:latn].standard
      "#,##0.###"

  """
  @spec all_formats_for!(Localize.LanguageTag.t() | atom() | String.t()) :: map()
  def all_formats_for!(locale) do
    case all_formats_for(locale) do
      {:ok, formats} -> formats
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Returns the format definitions for a given locale and number system.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0` struct.

  * `number_system` is a number system name or type atom.
    The default is `:default`.

  ### Returns

  * `{:ok, Localize.Number.Format.t()}` with the format definitions.

  * `{:error, exception}` if the locale data cannot be loaded or
    the number system is not available.

  When the requested number system has no format data of its own in
  the locale, the formats inherit per-field from the locale's default
  number system. This mirrors CLDR inheritance, where root aliases
  every other numbering system's formats to `latn`, and is what makes
  a `-u-nu-` override such as `en-u-nu-thai` formattable.

  ### Examples

      iex> {:ok, formats} = Localize.Number.Format.formats_for(:en)
      iex> formats.standard
      "#,##0.###"

      iex> {:ok, formats} = Localize.Number.Format.formats_for(:en, :thai)
      iex> formats.standard
      "#,##0.###"

  """
  @spec formats_for(
          Localize.LanguageTag.t() | atom() | String.t(),
          atom() | String.t()
        ) ::
          {:ok, t()} | {:error, Exception.t()}
  def formats_for(locale, number_system \\ :default) do
    with {:ok, system_name} <- System.system_name_from(number_system, locale),
         {:ok, formats} <- all_formats_for(locale) do
      requested = Map.get(formats, system_name)

      case merge_with_default_formats(requested, formats, locale, system_name) do
        nil ->
          {:error,
           Localize.InvalidValueError.exception(
             value: number_system,
             expected: "a number system with formats for this locale",
             context: "Localize.Number.Format.formats_for/2"
           )}

        format ->
          {:ok, format}
      end
    end
  end

  # CLDR inheritance: format elements for a numbering system the locale
  # carries no data for (or only partial data for) inherit from the
  # locale's default numbering system — root aliases them to `latn`.
  # Each field inherits independently, so a partially-populated entry
  # (for example `zh`'s `:hans` entry, which is present but empty) is
  # filled from the default system rather than left with `nil` patterns.
  defp merge_with_default_formats(requested, all_formats, locale, system_name) do
    # The locale's default system must be read from the locale data,
    # not from `number_system_from_locale/1` — the latter honours a
    # `-u-nu-` override, which is exactly the system we may be
    # trying to find a fallback for.
    case System.number_systems_for(locale) do
      {:ok, %{default: default_system}} when default_system != system_name ->
        merge_formats(requested, Map.get(all_formats, default_system))

      _default_or_error ->
        requested
    end
  end

  defp merge_formats(nil, default_formats), do: default_formats
  defp merge_formats(requested, nil), do: requested

  defp merge_formats(requested, default_formats) do
    Map.merge(default_formats, requested, fn _field, default, override ->
      override || default
    end)
  end

  @doc """
  Same as `formats_for/2` but raises on error.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0` struct.

  * `number_system` is a number system name or type atom.
    The default is `:default`.

  ### Returns

  * A `Localize.Number.Format.t()` struct.

  ### Raises

  * Raises an exception if the locale or number system is invalid.

  ### Examples

      iex> Localize.Number.Format.formats_for!(:en).percent
      "#,##0%"

  """
  @spec formats_for!(
          Localize.LanguageTag.t() | atom() | String.t(),
          atom() | String.t()
        ) :: t()
  def formats_for!(locale, number_system \\ :default) do
    case formats_for(locale, number_system) do
      {:ok, formats} -> formats
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Returns the minimum grouping digits for a locale.

  This determines the minimum number of digits before grouping
  separators are applied. For example, if the minimum is 2, the
  number 1000 would be formatted as "1000" rather than "1,000".

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0` struct.

  ### Returns

  * `{:ok, minimum_digits}` where `minimum_digits` is a
    non-negative integer.

  * `{:error, exception}` if the locale data cannot be loaded.

  ### Examples

      iex> Localize.Number.Format.minimum_grouping_digits_for(:en)
      {:ok, 1}

  """
  @spec minimum_grouping_digits_for(Localize.LanguageTag.t() | atom() | String.t()) ::
          {:ok, non_neg_integer()} | {:error, Exception.t()}
  def minimum_grouping_digits_for(locale) do
    with {:ok, locale_id} <- cldr_locale_id_from(locale) do
      Localize.Locale.get(locale_id, [:minimum_grouping_digits])
    end
  end

  @doc """
  Same as `minimum_grouping_digits_for/1` but raises on error.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0` struct.

  ### Returns

  * The minimum grouping digits as an integer.

  ### Raises

  * Raises an exception if the locale data cannot be loaded.

  ### Examples

      iex> Localize.Number.Format.minimum_grouping_digits_for!(:en)
      1

  """
  @spec minimum_grouping_digits_for!(Localize.LanguageTag.t() | atom() | String.t()) ::
          non_neg_integer()
  def minimum_grouping_digits_for!(locale) do
    case minimum_grouping_digits_for(locale) do
      {:ok, digits} -> digits
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Returns the default grouping definition for a locale.

  The grouping defines how integer and fraction digits are
  grouped with separators in the standard number format.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0` struct.

  ### Returns

  * `{:ok, grouping}` where `grouping` is a map with
    `:integer` and `:fraction` keys, each containing
    `:first` and `:rest` group sizes.

  * `{:error, exception}` if the locale data cannot be loaded.

  ### Examples

      iex> Localize.Number.Format.default_grouping_for(:en)
      {:ok, %{fraction: %{first: 0, rest: 0}, integer: %{first: 3, rest: 3}}}

  """
  @spec default_grouping_for(Localize.LanguageTag.t() | atom() | String.t()) ::
          {:ok, map()} | {:error, Exception.t()}
  def default_grouping_for(locale) do
    with {:ok, formats} <- formats_for(locale, :default) do
      standard_format = formats.standard || "#,##0.###"
      grouping = extract_grouping(standard_format)
      {:ok, grouping}
    end
  end

  @doc """
  Same as `default_grouping_for/1` but raises on error.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0` struct.

  ### Returns

  * A grouping map.

  ### Raises

  * Raises an exception if the locale data cannot be loaded.

  ### Examples

      iex> Localize.Number.Format.default_grouping_for!(:en)
      %{fraction: %{first: 0, rest: 0}, integer: %{first: 3, rest: 3}}

  """
  @spec default_grouping_for!(Localize.LanguageTag.t() | atom() | String.t()) ::
          %{
            fraction: %{first: 0, rest: 0},
            integer: %{first: non_neg_integer(), rest: non_neg_integer()}
          }
  def default_grouping_for!(locale) do
    case default_grouping_for(locale) do
      {:ok, grouping} -> grouping
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Returns the currency spacing rules for a locale and number system.

  Currency spacing defines how to insert whitespace between
  a currency symbol and the adjacent number.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0` struct.

  * `number_system` is a number system name or type atom.
    The default is `:default`.

  ### Returns

  * A map with `:before_currency` and `:after_currency` keys,
    each containing spacing rules.

  * `{:error, exception}` if the locale data cannot be loaded.

  ### Examples

      iex> spacing = Localize.Number.Format.currency_spacing(:en)
      iex> spacing.before_currency.insert_between
      "\u00A0"

  """
  @spec currency_spacing(
          Localize.LanguageTag.t() | atom() | String.t(),
          atom() | String.t()
        ) :: map() | {:error, Exception.t()}
  def currency_spacing(locale, number_system \\ :default) do
    with {:ok, formats} <- formats_for(locale, number_system) do
      Map.get(formats, :currency_spacing)
    end
  end

  @doc """
  Returns the format styles available for a locale and number system.

  Format styles standardise access to formats for common use cases
  such as `:standard`, `:currency`, `:accounting`, `:scientific`,
  `:engineering`, `:percent`, etc.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0` struct.

  * `number_system` is a number system name or type atom.
    The default is `:default`.

  ### Returns

  * `{:ok, styles}` where `styles` is a list of format
    style atoms.

  * `{:error, exception}` if the locale data cannot be loaded.

  ### Examples

      iex> {:ok, styles} = Localize.Number.Format.format_styles_for(:en)
      iex> :standard in styles and :currency in styles
      true

  """
  @spec format_styles_for(
          Localize.LanguageTag.t() | atom() | String.t(),
          atom() | String.t()
        ) :: {:ok, [atom()]} | {:error, Exception.t()}
  def format_styles_for(locale, number_system \\ :default) do
    with {:ok, formats} <- formats_for(locale, number_system) do
      styles =
        formats
        |> Map.from_struct()
        |> Enum.reject(fn {k, v} -> is_nil(v) || k in @reject_styles end)
        |> Enum.map(fn {k, _v} -> k end)

      {:ok, styles}
    end
  end

  @doc """
  Returns the short format styles available for a locale and
  number system.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0` struct.

  * `number_system` is a number system name or type atom.
    The default is `:default`.

  ### Returns

  * `{:ok, styles}` where `styles` is a list of short format
    style atoms.

  * `{:error, exception}` if the locale data cannot be loaded.

  ### Examples

      iex> {:ok, styles} = Localize.Number.Format.short_format_styles_for(:en)
      iex> Enum.sort(styles)
      [:currency_short, :decimal_long, :decimal_short]

  """
  @dialyzer {:nowarn_function, short_format_styles_for: 1}
  @dialyzer {:nowarn_function, short_format_styles_for: 2}
  @spec short_format_styles_for(
          Localize.LanguageTag.t() | atom() | String.t(),
          atom() | String.t()
        ) :: {:ok, [atom()]} | {:error, Exception.t()}
  def short_format_styles_for(locale, number_system \\ :default) do
    with {:ok, styles} <- format_styles_for(locale, number_system) do
      short =
        styles
        |> MapSet.new()
        |> MapSet.intersection(@short_formats)
        |> MapSet.to_list()

      {:ok, short}
    end
  end

  @doc """
  Returns the number system types available for a locale.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0` struct.

  ### Returns

  * `{:ok, types}` where `types` is a list of system type atoms
    (e.g., `[:default, :native]`).

  * `{:error, exception}` if the locale data cannot be loaded.

  ### Examples

      iex> Localize.Number.Format.format_system_types_for(:en)
      {:ok, [:default, :native]}

  """
  @spec format_system_types_for(Localize.LanguageTag.t() | atom() | String.t()) ::
          {:ok, [atom()]} | {:error, Exception.t()}
  def format_system_types_for(locale) do
    with {:ok, systems} <- System.number_systems_for(locale) do
      {:ok, Map.keys(systems)}
    end
  end

  @doc """
  Returns the number system names available for a locale.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0` struct.

  ### Returns

  * `{:ok, names}` where `names` is a list of unique number
    system name atoms.

  * `{:error, exception}` if the locale data cannot be loaded.

  ### Examples

      iex> Localize.Number.Format.format_system_names_for(:th)
      {:ok, [:latn, :thai]}

  """
  @spec format_system_names_for(Localize.LanguageTag.t() | atom() | String.t()) ::
          {:ok, [atom()]} | {:error, Exception.t()}
  def format_system_names_for(locale) do
    System.number_system_names_for(locale)
  end

  @doc """
  Returns the miscellaneous number patterns for a locale and
  number system.

  These patterns include range, approximately, at-least, and
  at-most formatting templates.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0`.

  * `number_system` is a number system name atom. The default
    is `:latn`.

  ### Returns

  * `{:ok, patterns}` where `patterns` is a map with keys
    `:range`, `:approximately`, `:at_least`, and `:at_most`.

  * `{:error, exception}` if the locale or number system data
    cannot be loaded.

  ### Examples

      iex> {:ok, patterns} = Localize.Number.Format.misc_patterns_for(:en)
      iex> patterns.range
      [0, "–", 1]

  """
  @spec misc_patterns_for(Localize.locale(), atom()) ::
          {:ok, map()} | {:error, Exception.t()}
  def misc_patterns_for(locale, number_system \\ :latn) do
    with {:ok, locale_id} <- cldr_locale_id_from(locale) do
      Localize.Locale.get(locale_id, [:number_formats, number_system, :other])
    end
  end

  # ── Private helpers ──────────────────────────────────────────

  defp cldr_locale_id_from(locale), do: Localize.Locale.cldr_locale_id_from(locale)

  # Extract grouping from a standard format pattern string.
  # Parses patterns like "#,##0.###" or "#,##,##0.###".
  defp extract_grouping(format_string) when is_binary(format_string) do
    # Split on semicolon to get positive pattern only
    positive = format_string |> String.split(";") |> hd()

    # Split on decimal point
    [integer_part | fraction_parts] = String.split(positive, ".")

    integer_grouping = extract_integer_grouping(integer_part)
    fraction_grouping = extract_fraction_grouping(List.first(fraction_parts))

    %{integer: integer_grouping, fraction: fraction_grouping}
  end

  defp extract_integer_grouping(integer_part) do
    # Split on commas and reverse so the group nearest the decimal
    # point is first. For "#,##0" → ["##0", "#"]; for
    # "#,##,##0" → ["##0", "##", "#"].
    groups =
      integer_part
      |> String.split(",")
      |> Enum.reverse()

    case groups do
      [_single] ->
        %{first: 0, rest: 0}

      [first_group] ++ rest_groups ->
        first_size = String.length(first_group)

        # The "rest" size is the second group if there are 3+ comma-
        # separated segments (e.g., Indian "#,##,##0" → rest is 2).
        # When there are only two segments, rest equals first (standard
        # grouping like "#,##0" → both are 3).
        rest_size =
          case rest_groups do
            [second | _more] when length(rest_groups) > 1 ->
              String.length(second)

            _ ->
              first_size
          end

        %{first: first_size, rest: rest_size}
    end
  end

  defp extract_fraction_grouping(nil), do: %{first: 0, rest: 0}
  defp extract_fraction_grouping(_fraction_part), do: %{first: 0, rest: 0}
end
