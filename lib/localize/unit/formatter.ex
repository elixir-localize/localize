defmodule Localize.Unit.Formatter do
  @moduledoc false

  alias Localize.Utils.Helpers

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
  # * `:format` — `:long`, `:short`, or `:narrow` (default `:long`).
  # * `:backend` — `:nif` or `:elixir` (default `:elixir`).
  #
  # ### Returns
  # * `{:ok, formatted_string}` or `{:error, exception}`.
  @spec to_string(Localize.Unit.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def to_string(%Localize.Unit{} = unit, options \\ []) do
    case Localize.Backend.resolve(options) do
      :nif ->
        locale = Keyword.get(options, :locale, Localize.get_locale())
        locale_string = locale_to_string(locale)
        Localize.Nif.unit_format(unit.value, unit.name, locale_string, options)

      :elixir ->
        locale = Keyword.get(options, :locale, Localize.get_locale())
        format = Keyword.get(options, :format, Keyword.get(options, :style, :long))

        with {:ok, language_tag} <- Localize.validate_locale(locale),
             {:ok, unit_data} <- load_unit_data(language_tag, format),
             {:ok, formatted} <- format_unit(unit, unit_data, language_tag, format, options) do
          {:ok, formatted}
        end
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

  defp format_unit(
         %Localize.Unit{value: value, name: name, parsed: parsed},
         unit_data,
         locale,
         _style,
         options
       ) do
    case currency_unit_parts(parsed) do
      {:ok, currency_code, denominator_units} ->
        format_currency_unit(value, currency_code, denominator_units, unit_data, locale, options)

      :not_currency ->
        unit_name = normalize_unit_name(name)

        case find_unit_formats(unit_data, unit_name) do
          nil ->
            format_fallback(value, name, options)

          unit_formats ->
            grammatical_case = Keyword.get(options, :grammatical_case, :nominative)
            format_with_pattern(value, unit_formats, locale, grammatical_case, options)
        end
    end
  end

  defp currency_unit_parts({:unit, keyword}) do
    numerator = Keyword.get(keyword, :numerator, [])
    denominator = Keyword.get(keyword, :denominator, [])

    case numerator do
      [{:single_unit, kw}] ->
        case Keyword.fetch!(kw, :base) do
          "curr-" <> code -> {:ok, code, denominator}
          _ -> :not_currency
        end

      _ ->
        :not_currency
    end
  end

  defp currency_unit_parts(_), do: :not_currency

  defp format_currency_unit(value, currency_code, denominator_units, unit_data, locale, options) do
    currency_atom = String.to_atom(currency_code)
    currency_options = Keyword.merge(options, currency: currency_atom, locale: locale)

    with {:ok, currency_string} <- format_number(value, currency_options) do
      case extract_denominator_parts(denominator_units) do
        {nil, nil} ->
          {:ok, currency_string}

        {count, denominator_base} ->
          denominator_name = normalize_unit_name(denominator_base)

          case find_per_unit_pattern(unit_data, denominator_name, value, locale) do
            nil ->
              per_part = if count, do: "#{count} #{denominator_base}", else: denominator_base
              {:ok, "#{currency_string} per #{per_part}"}

            pattern ->
              currency_with_count =
                if count do
                  result = Localize.Substitution.substitute(currency_string, pattern)
                  per_string = result |> :erlang.iolist_to_binary() |> String.trim()
                  # Insert the count before the denominator unit name in the pattern
                  String.replace(per_string, "per ", "per #{count} ")
                else
                  result = Localize.Substitution.substitute(currency_string, pattern)
                  result |> :erlang.iolist_to_binary() |> String.trim()
                end

              {:ok, currency_with_count}
          end
      end
    end
  end

  defp extract_denominator_parts([]), do: {nil, nil}

  defp extract_denominator_parts(units) do
    constant =
      Enum.find_value(units, fn
        {:constant, value} -> value
        _ -> nil
      end)

    single_unit_base =
      Enum.find_value(units, fn
        {:single_unit, kw} -> Keyword.fetch!(kw, :base)
        _ -> nil
      end)

    {constant, single_unit_base}
  end

  defp find_per_unit_pattern(unit_data, denominator_name, _value, _locale) do
    denominator_atom = safe_to_atom(denominator_name)

    per_unit_pattern =
      Enum.find_value(unit_data, fn
        {_category, units} when is_map(units) ->
          case Map.get(units, denominator_atom) || Map.get(units, denominator_name) do
            %{per_unit_pattern: pattern} -> pattern
            _ -> nil
          end

        _ ->
          nil
      end)

    case per_unit_pattern do
      [position, pattern_str] when is_integer(position) ->
        unit_pattern_to_tokens(position, pattern_str)

      tokens when is_list(tokens) ->
        tokens

      _ ->
        nil
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

      tokens when is_list(tokens) ->
        # Substitution-format pattern like ["華氏 ", 0, " 度"]
        with {:ok, number_str} <- format_number(value, options) do
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

  @number_format_options [
    :locale,
    :fractional_digits,
    :min_fractional_digits,
    :max_fractional_digits,
    :currency
  ]

  defp format_number(value, options) do
    number_options = Keyword.take(options, @number_format_options)
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

  defp safe_to_atom(string) when is_binary(string), do: Helpers.existing_atom(string) || string

  defp locale_to_string(%Localize.LanguageTag{} = tag), do: Localize.LanguageTag.to_string(tag)
  defp locale_to_string(locale) when is_atom(locale), do: Atom.to_string(locale)
  defp locale_to_string(locale) when is_binary(locale), do: locale
  defp locale_to_string(_), do: "en"
end
