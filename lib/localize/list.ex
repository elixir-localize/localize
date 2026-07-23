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

  ## Element formatting

  Each list element is formatted with `Localize.to_string/2`, which
  dispatches via the `Localize.Chars` protocol. Strings pass through
  unchanged. Numbers, dates, units, durations, currencies and any
  other type with a `Localize.Chars` implementation are formatted
  in a locale-aware way using the same locale (and any other
  forwarded options) as the outer list call. Types with no
  `Localize.Chars` implementation fall through to `Kernel.to_string/1`.

      iex> Localize.List.to_string([~D[2025-07-10], ~D[2025-08-15]], locale: :en)
      {:ok, "Jul 10, 2025 and Aug 15, 2025"}

      iex> Localize.List.to_string([1234, 5678], locale: :de)
      {:ok, "1.234 und 5.678"}

  Options that are specific to list formatting (`:list_style`,
  `:treat_middle_as_end`) are stripped before being passed to the
  per-element formatters. Everything else (`:locale`, `:format`,
  `:currency`, `:prefer`, etc.) is forwarded so that, for example,
  a list of numbers can pick up a single `currency: :USD` option,
  or a list of dates can pick up a single `format: :long` option:

      iex> Localize.List.to_string([1234.56, 5678.90], locale: :en, currency: :USD)
      {:ok, "$1,234.56 and $5,678.90"}

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

  @default_list_style :standard

  # Options consumed by `Localize.List` itself that must not be
  # passed through to per-element formatters. `:list_style`
  # selects the CLDR list pattern; `:treat_middle_as_end` controls
  # which pattern is applied to the last element. Neither has a
  # meaning for per-element formatters.
  @list_specific_options [:list_style, :treat_middle_as_end]

  @doc """
  Formats a list into a string according to the list pattern
  rules for a locale.

  ### Arguments

  * `list` is a list of terms that can be passed through
    `Kernel.to_string/1`.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is
    `Localize.get_locale/0`.

  * `:list_style` is an atom from `known_list_styles/0` or a
    `t:Localize.List.Pattern.t/0`. Selects the CLDR list pattern
    used to join the elements (`:standard`, `:or`, `:unit_narrow`,
    etc.). The default is `:standard`.

  * `:treat_middle_as_end` is a boolean. When `true`, the
    `:middle` pattern is used for the last element instead
    of the `:end` pattern. The default is `false`.

  All other options (e.g. `:format`, `:currency`, `:prefer`) are
  forwarded to the per-element formatters via `Localize.to_string/2`.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, exception}` if the locale or list style is invalid.

  ### Examples

      iex> Localize.List.to_string(["a", "b", "c"], locale: :en)
      {:ok, "a, b, and c"}

      iex> Localize.List.to_string(["a", "b", "c"], locale: :en, list_style: :unit_narrow)
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
    element_options = Keyword.drop(options, @list_specific_options)

    with {:ok, interspersed} <- intersperse(list, options),
         {:ok, parts} <- format_elements(interspersed, element_options) do
      {:ok, :erlang.iolist_to_binary(parts)}
    end
  end

  defp format_elements(elements, options) do
    Enum.reduce_while(elements, {:ok, []}, fn elem, {:ok, acc} ->
      case format_element(elem, options) do
        {:ok, string} -> {:cont, {:ok, [acc, string]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  # Strings (both original list elements and the separator strings
  # inserted by `intersperse/2`) pass through unchanged. Anything
  # else is dispatched through the `Localize.Chars` protocol so
  # that numbers, dates, units, etc. pick up the outer locale.
  defp format_element(elem, _options) when is_binary(elem), do: {:ok, elem}
  defp format_element(elem, options), do: Localize.to_string(elem, options)

  @doc """
  Same as `to_string/2` but raises on error.

  ### Arguments

  * `list` is a list of terms.

  * `options` is a keyword list of options.

  ### Options

  * See `to_string/2` for the supported options.

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
  Formats a list into typed parts, mirroring ECMA-402's `formatToParts` for `Intl.ListFormat`.

  The parts concatenate to exactly the string `to_string/2` produces with the same options. Each list element becomes an `:element` part (formatted through the same per-element dispatch as `to_string/2`) and each pattern separator becomes a `:literal` part.

  ### Arguments

  * `list` is a list of terms.

  * `options` is a keyword list of options.

  ### Options

  See `to_string/2` for the supported options.

  ### Returns

  * `{:ok, parts}` where `parts` is a list of `%{type: atom(), value: String.t()}` maps.

  * `{:error, exception}` if the locale or list style is invalid.

  ### Examples

      iex> Localize.List.to_parts(["a", "b", "c"], locale: :en)
      {:ok,
       [
         %{type: :element, value: "a"},
         %{type: :literal, value: ", "},
         %{type: :element, value: "b"},
         %{type: :literal, value: ", and "},
         %{type: :element, value: "c"}
       ]}

      iex> Localize.List.to_parts(["a"], locale: :en)
      {:ok, [%{type: :element, value: "a"}]}

  """
  @spec to_parts([term()], Keyword.t()) ::
          {:ok, [%{type: atom(), value: String.t()}]} | {:error, Exception.t()}
  def to_parts(list, options \\ []) do
    element_options = Keyword.drop(options, @list_specific_options)

    with {:ok, pattern, middle_as_end?} <- normalize_options(options),
         {:ok, element_parts} <- elements_to_parts(list, element_options) do
      {:ok, do_intersperse_parts(element_parts, pattern, middle_as_end?)}
    end
  end

  @doc """
  Same as `to_parts/2` but raises on error.

  ### Arguments

  * `list` is a list of terms.

  * `options` is a keyword list of options. See `to_parts/2`.

  ### Returns

  * A list of `%{type: atom(), value: String.t()}` maps.

  ### Raises

  * Raises an exception if the list cannot be formatted.

  ### Examples

      iex> Localize.List.to_parts!(["a", "b"], locale: :en)
      [
        %{type: :element, value: "a"},
        %{type: :literal, value: " and "},
        %{type: :element, value: "b"}
      ]

  """
  @spec to_parts!([term()], Keyword.t()) :: [%{type: atom(), value: String.t()}]
  def to_parts!(list, options \\ []) do
    case to_parts(list, options) do
      {:ok, parts} -> parts
      {:error, exception} -> raise exception
    end
  end

  defp elements_to_parts(list, options) do
    result =
      Enum.reduce_while(list, {:ok, []}, fn elem, {:ok, acc} ->
        case format_element(elem, options) do
          {:ok, string} -> {:cont, {:ok, [[%{type: :element, value: string}] | acc]}}
          {:error, _} = error -> {:halt, error}
        end
      end)

    case result do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      {:error, _} = error -> error
    end
  end

  # The parts sibling of `do_intersperse/3`: identical recursion over
  # the CLDR list pattern tree with parts lists in place of iodata.
  defp do_intersperse_parts([], _pattern, _middle_as_end?), do: []

  defp do_intersperse_parts([single], _pattern, _middle_as_end?), do: single

  defp do_intersperse_parts([first, last], pattern, false = _middle_as_end?) do
    Substitution.substitute_parts([first, last], pattern.two)
  end

  defp do_intersperse_parts([first, last], pattern, true = _middle_as_end?) do
    Substitution.substitute_parts([first, last], pattern.start)
  end

  defp do_intersperse_parts([first, middle, last], pattern, false = _middle_as_end?) do
    last_pair = Substitution.substitute_parts([middle, last], pattern.end)
    Substitution.substitute_parts([first, last_pair], pattern.start)
  end

  defp do_intersperse_parts([first, middle, last], pattern, true = _middle_as_end?) do
    last_pair = Substitution.substitute_parts([middle, last], pattern.middle)
    Substitution.substitute_parts([first, last_pair], pattern.start)
  end

  defp do_intersperse_parts([first | rest], pattern, middle_as_end?) do
    remaining = do_intersperse_parts(rest, pattern, middle_as_end?)
    Substitution.substitute_parts([first, remaining], pattern.start)
  end

  @doc """
  Intersperses list elements with locale-appropriate separators.

  This function returns a list with separator strings inserted
  between elements, which is useful for building safe HTML or
  other non-string output.

  ### Arguments

  * `list` is a list of terms.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is
    `Localize.get_locale/0`.

  * `:list_style` is an atom from `known_list_styles/0` or a
    `t:Localize.List.Pattern.t/0`. Selects the CLDR list pattern
    used to derive the separators. The default is `:standard`.

  * `:treat_middle_as_end` is a boolean. When `true`, the
    `:middle` pattern is used for the last element instead
    of the `:end` pattern. The default is `false`.

  Unlike `to_string/2`, elements are not formatted, so
  per-element formatter options have no effect here.

  ### Returns

  * `{:ok, interspersed_list}` on success.

  * `{:error, exception}` if the locale or format is invalid.

  ### Examples

      iex> Localize.List.intersperse(["a", "b", "c"], locale: :en)
      {:ok, ["a", ", ", "b", ", and ", "c"]}

      iex> Localize.List.intersperse(["a", "b", "c"], locale: :en, list_style: :unit_narrow)
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

  ### Options

  * See `intersperse/2` for the supported options.

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
    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, formats} <- Localize.Locale.get(locale_id, [:list_formats]) do
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
  Returns the list style names available for a locale.

  ### Arguments

  * `locale` is a locale identifier.

  ### Returns

  * `{:ok, list_styles}` where `list_styles` is a sorted
    list of atoms.

  * `{:error, exception}` if the locale is invalid.

  ### Examples

      iex> Localize.List.list_styles_for(:en)
      {:ok, [:or, :or_narrow, :or_short, :standard, :standard_narrow, :standard_short, :unit, :unit_narrow, :unit_short]}

  """
  @spec list_styles_for(atom() | String.t()) :: {:ok, [atom()]} | {:error, Exception.t()}
  def list_styles_for(locale) do
    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, formats} <- Localize.Locale.get(locale_id, [:list_formats]) do
      {:ok, formats |> Map.keys() |> Enum.sort()}
    end
  end

  @doc """
  Returns the list of known list style names.

  ### Returns

  * A list of atoms representing the known list style names.

  ### Examples

      iex> Localize.List.known_list_styles()
      [:or, :or_narrow, :or_short, :standard, :standard_narrow, :standard_short, :unit, :unit_narrow, :unit_short]

  """
  @spec known_list_styles() :: [
          :or
          | :or_narrow
          | :or_short
          | :standard
          | :standard_narrow
          | :standard_short
          | :unit
          | :unit_narrow
          | :unit_short,
          ...
        ]
  def known_list_styles do
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
    list_style = Keyword.get(options, :list_style, @default_list_style)
    middle_as_end? = !!Keyword.get(options, :treat_middle_as_end, false)

    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, pattern} <- resolve_list_style(locale_id, list_style) do
      {:ok, pattern, middle_as_end?}
    end
  end

  defp resolve_locale_id(locale), do: Localize.Locale.cldr_locale_id_from(locale)

  defp resolve_list_style(_locale_id, %Pattern{} = pattern) do
    {:ok, pattern}
  end

  defp resolve_list_style(locale_id, list_style) when is_atom(list_style) do
    with {:ok, formats} <- Localize.Locale.get(locale_id, [:list_formats]) do
      case Map.get(formats, list_style) do
        nil ->
          {:error,
           Localize.InvalidValueError.exception(
             value: list_style,
             expected: "a known list style",
             context: "Localize.List"
           )}

        data ->
          {:ok, Pattern.from_locale_data(data)}
      end
    end
  end

  # ── Helpers ────────────────────────────────────────────────
end
