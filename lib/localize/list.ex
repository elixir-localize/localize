defmodule Localize.List do
  @moduledoc """
  Formats lists into locale-aware strings using CLDR list
  formatting patterns.

  For example, a list of days like `["Monday", "Tuesday", "Wednesday"]`
  can be formatted for a given locale:

      iex> Localize.List.to_string(["Monday", "Tuesday", "Wednesday"], locale: :en)
      {:ok, "Monday, Tuesday, and Wednesday"}

      iex> Localize.List.to_string(["Monday", "Tuesday", "Wednesday"], locale: :fr)
      {:ok, "Monday, Tuesday et Wednesday"}

  """

  import Kernel, except: [to_string: 1]

  alias Localize.List.Pattern
  alias Localize.Substitution

  @type pattern_type ::
          :or
          | :or_narrow
          | :or_short
          | :standard
          | :standard_narrow
          | :standard_short
          | :unit
          | :unit_narrow
          | :unit_short

  @default_format :standard

  @doc """
  Formats a list into a string according to the list pattern
  rules for a locale.

  ### Arguments

  * `list` is a list of terms that can be passed through
    `Kernel.to_string/1`.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is `:en`.

  * `:format` is an atom from `known_list_formats/0` or a
    `t:Localize.List.Pattern.t/0`. The default is `:standard`.

  * `:treat_middle_as_end` is a boolean. When `true`, the
    `:middle` pattern is used for the last element instead
    of the `:end` pattern. The default is `false`.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, exception}` if the locale or format is invalid.

  ### Examples

      iex> Localize.List.to_string(["a", "b", "c"], locale: :en)
      {:ok, "a, b, and c"}

      iex> Localize.List.to_string(["a", "b", "c"], locale: :en, format: :unit_narrow)
      {:ok, "a b c"}

      iex> Localize.List.to_string(["a"], locale: :en)
      {:ok, "a"}

      iex> Localize.List.to_string([1, 2], locale: :en)
      {:ok, "1 and 2"}

      iex> Localize.List.to_string([1, 2, 3, 4, 5, 6], locale: :en)
      {:ok, "1, 2, 3, 4, 5, and 6"}

  """
  @spec to_string([term()], Keyword.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def to_string(list, options \\ []) do
    with {:ok, interspersed} <- intersperse(list, options) do
      string =
        interspersed
        |> Enum.map(&Kernel.to_string/1)
        |> :erlang.iolist_to_binary()

      {:ok, string}
    end
  end

  @doc """
  Same as `to_string/2` but raises on error.

  ### Arguments

  * `list` is a list of terms.

  * `options` is a keyword list of options.

  ### Returns

  * A formatted string.

  ### Examples

      iex> Localize.List.to_string!(["a", "b", "c"], locale: :en)
      "a, b, and c"

  """
  @spec to_string!([term()], Keyword.t()) :: String.t()
  def to_string!(list, options \\ []) do
    case to_string(list, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Intersperses list elements with locale-appropriate separators.

  This function returns a list with separator strings inserted
  between elements, which is useful for building safe HTML or
  other non-string output.

  ### Arguments

  * `list` is a list of terms.

  * `options` is a keyword list of options. Same options as
    `to_string/2`.

  ### Returns

  * `{:ok, interspersed_list}` on success.

  * `{:error, exception}` if the locale or format is invalid.

  ### Examples

      iex> Localize.List.intersperse(["a", "b", "c"], locale: :en)
      {:ok, ["a", ", ", "b", ", and ", "c"]}

      iex> Localize.List.intersperse(["a", "b", "c"], locale: :en, format: :unit_narrow)
      {:ok, ["a", " ", "b", " ", "c"]}

      iex> Localize.List.intersperse(["a"], locale: :en)
      {:ok, ["a"]}

      iex> Localize.List.intersperse([1, 2], locale: :en)
      {:ok, [1, " and ", 2]}

  """
  @spec intersperse([term()], Keyword.t()) :: {:ok, [term()]} | {:error, Exception.t()}
  def intersperse(list, options \\ [])

  def intersperse([], _options) do
    {:ok, []}
  end

  def intersperse(list, options) do
    with {:ok, pattern, middle_as_end?} <- normalize_options(options) do
      result =
        list
        |> do_intersperse(pattern, middle_as_end?)
        |> List.flatten()

      {:ok, result}
    end
  end

  @doc """
  Same as `intersperse/2` but raises on error.

  ### Arguments

  * `list` is a list of terms.

  * `options` is a keyword list of options.

  ### Returns

  * An interspersed list.

  ### Examples

      iex> Localize.List.intersperse!(["a", "b", "c"], locale: :en)
      ["a", ", ", "b", ", and ", "c"]

  """
  @spec intersperse!([term()], Keyword.t()) :: [term()]
  def intersperse!(list, options \\ []) do
    case intersperse(list, options) do
      {:ok, result} -> result
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Returns the list patterns for a locale.

  ### Arguments

  * `locale` is a locale identifier.

  ### Returns

  * `{:ok, patterns_map}` where each value is a
    `t:Localize.List.Pattern.t/0`.

  * `{:error, exception}` if the locale is invalid.

  ### Examples

      iex> {:ok, patterns} = Localize.List.list_patterns_for(:en)
      iex> Map.keys(patterns) |> Enum.sort()
      [:or, :or_narrow, :or_short, :standard, :standard_narrow, :standard_short, :unit, :unit_narrow, :unit_short]

  """
  @spec list_patterns_for(atom() | String.t()) :: {:ok, map()} | {:error, Exception.t()}
  def list_patterns_for(locale) do
    locale_id = locale_id(locale)

    with {:ok, formats} <- Localize.Locale.get(locale_id, [:list_formats]) do
      patterns =
        formats
        |> Enum.map(fn {format_name, data} ->
          {format_name, Pattern.from_locale_data(data)}
        end)
        |> Map.new()

      {:ok, patterns}
    end
  end

  @doc """
  Returns the available list format names for a locale.

  ### Arguments

  * `locale` is a locale identifier.

  ### Returns

  * `{:ok, format_names}` where `format_names` is a sorted
    list of atoms.

  * `{:error, exception}` if the locale is invalid.

  ### Examples

      iex> Localize.List.list_formats_for(:en)
      {:ok, [:or, :or_narrow, :or_short, :standard, :standard_narrow, :standard_short, :unit, :unit_narrow, :unit_short]}

  """
  @spec list_formats_for(atom() | String.t()) :: {:ok, [atom()]} | {:error, Exception.t()}
  def list_formats_for(locale) do
    locale_id = locale_id(locale)

    with {:ok, formats} <- Localize.Locale.get(locale_id, [:list_formats]) do
      {:ok, formats |> Map.keys() |> Enum.sort()}
    end
  end

  @doc """
  Returns the list of known list format types.

  ### Returns

  * A list of atoms representing the known list format types.

  ### Examples

      iex> Localize.List.known_list_formats()
      [:or, :or_narrow, :or_short, :standard, :standard_narrow, :standard_short, :unit, :unit_narrow, :unit_short]

  """
  @spec known_list_formats() :: [atom()]
  def known_list_formats do
    [
      :or,
      :or_narrow,
      :or_short,
      :standard,
      :standard_narrow,
      :standard_short,
      :unit,
      :unit_narrow,
      :unit_short
    ]
  end

  # ── Core intersperse algorithm ─────────────────────────────

  # Empty list
  defp do_intersperse([], _pattern, _middle_as_end?) do
    []
  end

  # Single element
  defp do_intersperse([first], _pattern, _middle_as_end?) do
    [first]
  end

  # Two elements
  defp do_intersperse([first, last], pattern, false = _middle_as_end?) do
    Substitution.substitute([first, last], pattern.two)
  end

  defp do_intersperse([first, last], pattern, true = _middle_as_end?) do
    Substitution.substitute([first, last], pattern.start)
  end

  # Three elements
  defp do_intersperse([first, middle, last], pattern, false = _middle_as_end?) do
    last_pair = Substitution.substitute([middle, last], pattern.end)
    Substitution.substitute([first, last_pair], pattern.start)
  end

  defp do_intersperse([first, middle, last], pattern, true = _middle_as_end?) do
    last_pair = Substitution.substitute([middle, last], pattern.middle)
    Substitution.substitute([first, last_pair], pattern.start)
  end

  # Four or more elements
  defp do_intersperse([first | rest], pattern, middle_as_end?) do
    remaining = do_intersperse(rest, pattern, middle_as_end?)
    Substitution.substitute([first, remaining], pattern.start)
  end

  # ── Options normalization ──────────────────────────────────

  defp normalize_options(options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    format = Keyword.get(options, :format, @default_format)
    middle_as_end? = !!Keyword.get(options, :treat_middle_as_end, false)

    locale_id = locale_id(locale)

    with {:ok, pattern} <- resolve_format(locale_id, format) do
      {:ok, pattern, middle_as_end?}
    end
  end

  defp resolve_format(_locale_id, %Pattern{} = pattern) do
    {:ok, pattern}
  end

  defp resolve_format(locale_id, format) when is_atom(format) do
    with {:ok, formats} <- Localize.Locale.get(locale_id, [:list_formats]) do
      case Map.get(formats, format) do
        nil ->
          {:error,
           Localize.InvalidValueError.exception(
             value: format,
             expected: "a known list format",
             context: "Localize.List"
           )}

        data ->
          {:ok, Pattern.from_locale_data(data)}
      end
    end
  end

  # ── Helpers ────────────────────────────────────────────────

  defp locale_id(%Localize.LanguageTag{cldr_locale_id: id}) when not is_nil(id), do: id
  defp locale_id(locale) when is_atom(locale), do: locale
  defp locale_id(locale) when is_binary(locale), do: String.to_existing_atom(locale)
end
