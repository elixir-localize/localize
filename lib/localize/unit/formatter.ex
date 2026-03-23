defmodule Localize.Unit.Formatter do
  @moduledoc false

  import Kernel, except: [to_string: 1]

  # Formats a Localize.Unit struct into a localized string.
  #
  # The formatter:
  # 1. Loads unit format patterns from locale data
  # 2. Determines the plural form for the number
  # 3. Looks up the pattern (e.g., [0, " meters"])
  # 4. Formats the number using Localize.Number
  # 5. Substitutes the number into the pattern

  # # to_string/2
  # Formats a unit as a localized string.
  #
  # ### Arguments
  # * `unit` is a `Localize.Unit.t()` struct.
  # * `options` is a keyword list of options.
  #
  # ### Options
  # * `:locale` — locale identifier (default `:en`).
  # * `:style` — `:long`, `:short`, or `:narrow` (default `:long`).
  #
  # ### Returns
  # * `{:ok, formatted_string}` or `{:error, exception}`.
  @spec to_string(Localize.Unit.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def to_string(%Localize.Unit{} = unit, options \\ []) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    style = Keyword.get(options, :style, :long)

    with {:ok, language_tag} <- Localize.validate_locale(locale),
         {:ok, unit_data} <- load_unit_data(language_tag, style),
         {:ok, formatted} <- format_unit(unit, unit_data, language_tag, style, options) do
      {:ok, formatted}
    end
  end

  # ── Data loading ───────────────────────────────────────────

  defp load_unit_data(language_tag, style) do
    locale_id = locale_id(language_tag)

    with {:ok, all_units} <- Localize.Locale.get(locale_id, [:units]) do
      style_key = to_style_key(style)

      case Map.get(all_units, style_key) do
        nil ->
          {:error,
           Localize.InvalidValueError.exception(
             value: style,
             expected: "a valid unit style (:long, :short, :narrow)",
             context: "Localize.Unit.Formatter"
           )}

        data ->
          {:ok, data}
      end
    end
  end

  defp to_style_key(:long), do: :long
  defp to_style_key(:short), do: :short
  defp to_style_key(:narrow), do: :narrow
  defp to_style_key(style), do: style

  # ── Unit formatting ────────────────────────────────────────

  defp format_unit(%Localize.Unit{value: value, name: name}, unit_data, locale, _style, options) do
    unit_name = normalize_unit_name(name)

    case find_unit_formats(unit_data, unit_name) do
      nil ->
        # Fallback: just format as "number unit_name"
        format_fallback(value, name, options)

      unit_formats ->
        grammatical_case = Keyword.get(options, :grammatical_case, :nominative)
        format_with_pattern(value, unit_formats, locale, grammatical_case, options)
    end
  end

  defp format_with_pattern(nil, unit_formats, _locale, _case, _options) do
    # No value — return display name
    {:ok, Map.get(unit_formats, :display_name, "")}
  end

  defp format_with_pattern(value, unit_formats, locale, grammatical_case, options)
       when is_list(value) do
    # Mixed units — not yet supported, format the first value
    format_with_pattern(hd(value), unit_formats, locale, grammatical_case, options)
  end

  defp format_with_pattern(value, unit_formats, locale, grammatical_case, options) do
    # Determine plural form
    plural = plural_form(value, locale)

    # Get case forms, falling back to nominative
    case_forms =
      Map.get(unit_formats, grammatical_case) ||
        Map.get(unit_formats, :nominative) ||
        Map.get(unit_formats, :other)

    # Get the pattern for this plural form, falling back to :other
    pattern =
      cond do
        is_map(case_forms) ->
          Map.get(case_forms, plural) || Map.get(case_forms, :other)

        is_list(case_forms) ->
          case_forms

        true ->
          nil
      end

    case pattern do
      [position, pattern_str] when is_integer(position) and is_binary(pattern_str) ->
        with {:ok, number_str} <- format_number(value, options) do
          # Build a Substitution-compatible token list from position + pattern
          tokens = unit_pattern_to_tokens(position, pattern_str)
          result = Localize.Substitution.substitute(number_str, tokens)
          {:ok, result |> :erlang.iolist_to_binary() |> String.trim()}
        end

      nil ->
        format_fallback(value, Map.get(unit_formats, :display_name, ""), options)

      other when is_binary(other) ->
        with {:ok, number_str} <- format_number(value, options) do
          {:ok, "#{number_str} #{other}"}
        end
    end
  end

  # Converts the CLDR unit pattern [position, suffix] into a
  # Localize.Substitution-compatible token list.
  defp unit_pattern_to_tokens(0, pattern_str), do: [0, pattern_str]
  defp unit_pattern_to_tokens(1, pattern_str), do: [pattern_str, 0]
  defp unit_pattern_to_tokens(_, pattern_str), do: [0, pattern_str]

  # ── Number formatting ──────────────────────────────────────

  defp format_number(value, options) do
    number_options =
      options
      |> Keyword.take([:locale, :format, :fractional_digits, :currency])

    Localize.Number.to_string(value, number_options)
  end

  # ── Plural form resolution ────────────────────────────────

  defp plural_form(value, locale) when is_number(value) do
    Localize.Number.PluralRule.Cardinal.plural_rule(value, locale)
  end

  defp plural_form(%Decimal{} = value, locale) do
    Localize.Number.PluralRule.Cardinal.plural_rule(Decimal.to_float(value), locale)
  end

  defp plural_form(_value, _locale), do: :other

  # ── Unit name resolution ───────────────────────────────────

  defp find_unit_formats(unit_data, unit_name) do
    unit_atom = safe_to_atom(unit_name)

    # Search through all categories for this unit name
    Enum.find_value(unit_data, fn
      {_category, units} when is_map(units) ->
        Map.get(units, unit_atom) || Map.get(units, unit_name)

      _ ->
        nil
    end)
  end

  defp normalize_unit_name(name) when is_binary(name) do
    name
    |> String.replace("-", "_")
    |> String.downcase()
  end

  defp normalize_unit_name(name) when is_atom(name), do: Atom.to_string(name)

  # ── Fallback formatting ────────────────────────────────────

  defp format_fallback(nil, name, _options), do: {:ok, Kernel.to_string(name)}

  defp format_fallback(value, name, options) do
    with {:ok, number_str} <- format_number(value, options) do
      {:ok, "#{number_str} #{name}"}
    end
  end

  # ── Helpers ────────────────────────────────────────────────

  defp locale_id(%Localize.LanguageTag{cldr_locale_id: id}) when not is_nil(id), do: id
  defp locale_id(_), do: :en

  @dialyzer {:nowarn_function, safe_to_atom: 1}
  defp safe_to_atom(string) when is_binary(string) do
    String.to_existing_atom(string)
  rescue
    ArgumentError -> string
  end

  defp safe_to_atom(atom) when is_atom(atom), do: atom
end
