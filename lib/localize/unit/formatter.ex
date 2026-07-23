defmodule Localize.Unit.Formatter do
  @moduledoc false

  alias Localize.Utils.Helpers

  import Kernel, except: [to_string: 1]

  @number_format_options [
    :locale,
    :fractional_digits,
    :min_fractional_digits,
    :max_fractional_digits,
    :minimum_significant_digits,
    :maximum_significant_digits,
    :round_nearest,
    :rounding_mode,
    :grammatical_case,
    :grammatical_gender,
    :currency
  ]

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
    locale = Keyword.get(options, :locale, Localize.get_locale())
    format = Keyword.get(options, :format, :long)

    case Localize.Backend.resolve(options) do
      :nif ->
        # `Localize.Nif.unit_format/4` takes the ICU option name
        # `:style`; translate the public `:format` option so both
        # backends honour the same width.
        with {:ok, locale_string} <- validated_locale_string(locale) do
          Localize.Nif.unit_format(unit.value, unit.name, locale_string, style: format)
        end

      :elixir ->
        with {:ok, language_tag} <- Localize.validate_locale(locale),
             {:ok, unit_data} <- load_unit_data(language_tag, format) do
          format_unit(unit, unit_data, language_tag, format, options)
        end
    end
  end

  # # to_range_string/3
  #
  # Formats two units of the same kind as a localized range,
  # applying the unit pattern once per TR35: the numeric range is
  # substituted into the unit pattern for the range's plural
  # category (from the TR35 plural-range rules).
  @spec to_range_string(Localize.Unit.t(), Localize.Unit.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def to_range_string(unit_1, unit_2, options \\ [])

  def to_range_string(
        %Localize.Unit{name: name} = unit_1,
        %Localize.Unit{name: name} = unit_2,
        options
      ) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    format = Keyword.get(options, :format, :long)

    with {:ok, language_tag} <- Localize.validate_locale(locale),
         {:ok, unit_data} <- load_unit_data(language_tag, format),
         {:ok, tokens} <- range_pattern_tokens(unit_data, unit_1, unit_2, language_tag, options),
         {:ok, range_string} <-
           Localize.Number.to_range_string(
             unit_1.value,
             unit_2.value,
             Keyword.take(options, @number_format_options)
           ) do
      result = Localize.Substitution.substitute(range_string, tokens)
      {:ok, result |> :erlang.iolist_to_binary() |> String.trim()}
    end
  end

  def to_range_string(%Localize.Unit{} = unit_1, %Localize.Unit{} = unit_2, _options) do
    {:error,
     Localize.InvalidValueError.exception(
       value: {unit_1.name, unit_2.name},
       expected: "two units of the same kind",
       context: "Localize.Unit.to_range_string/3"
     )}
  end

  defp range_pattern_tokens(unit_data, unit_1, unit_2, language_tag, options) do
    unit_name = normalize_unit_name(unit_1.name)

    with unit_formats when is_map(unit_formats) <- find_unit_formats(unit_data, unit_name),
         {:ok, range_category} <-
           Localize.Number.PluralRule.Range.plural_rule_for(
             unit_1.value,
             unit_2.value,
             language_tag
           ),
         grammatical_case = Keyword.get(options, :grammatical_case, :nominative),
         tokens when is_list(tokens) <-
           pattern_tokens(resolve_pattern(unit_formats, grammatical_case, range_category)) do
      {:ok, tokens}
    else
      {:error, _reason} = error ->
        error

      _no_pattern ->
        {:error,
         Localize.InvalidValueError.exception(
           value: unit_1.name,
           expected: "a unit with a direct CLDR pattern",
           context: "Localize.Unit.to_range_string/3"
         )}
    end
  end

  # # to_range_parts/3
  #
  # The parts sibling of `to_range_string/3`: the numeric range's
  # parts (with their `:start_range` / `:end_range` / `:shared`
  # sources) substituted into the unit pattern, whose text becomes
  # `:unit` and `:literal` parts with source `:shared` per ECMA-402
  # `formatRangeToParts` for unit style.
  @spec to_range_parts(Localize.Unit.t(), Localize.Unit.t(), Keyword.t()) ::
          {:ok, [%{type: atom(), value: String.t(), source: atom()}]} | {:error, Exception.t()}
  def to_range_parts(unit_1, unit_2, options \\ [])

  def to_range_parts(
        %Localize.Unit{name: name} = unit_1,
        %Localize.Unit{name: name} = unit_2,
        options
      ) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    format = Keyword.get(options, :format, :long)

    with {:ok, language_tag} <- Localize.validate_locale(locale),
         {:ok, unit_data} <- load_unit_data(language_tag, format),
         {:ok, tokens} <- range_pattern_tokens(unit_data, unit_1, unit_2, language_tag, options),
         {:ok, range_parts} <-
           Localize.Number.to_range_parts(
             unit_1.value,
             unit_2.value,
             Keyword.take(options, @number_format_options)
           ) do
      parts =
        [range_parts]
        |> Localize.Substitution.substitute_parts(tokens, :unit)
        |> split_unit_whitespace()
        |> Enum.map(&Map.put_new(&1, :source, :shared))
        |> trim_edge_whitespace()

      {:ok, parts}
    end
  end

  def to_range_parts(%Localize.Unit{} = unit_1, %Localize.Unit{} = unit_2, _options) do
    {:error,
     Localize.InvalidValueError.exception(
       value: {unit_1.name, unit_2.name},
       expected: "two units of the same kind",
       context: "Localize.Unit.to_range_parts/3"
     )}
  end

  # `to_range_string/3` trims outer whitespace from the substituted
  # result; drop the equivalent whitespace-only edge literals so the
  # parts concatenate to the same string.
  defp trim_edge_whitespace(parts) do
    parts
    |> drop_edge_whitespace()
    |> Enum.reverse()
    |> drop_edge_whitespace()
    |> Enum.reverse()
  end

  defp drop_edge_whitespace([%{type: :literal, value: value} | rest] = parts) do
    if String.trim(value) == "", do: drop_edge_whitespace(rest), else: parts
  end

  defp drop_edge_whitespace(parts), do: parts

  # # to_parts/2
  #
  # Formats a unit into typed parts: the number's parts from
  # `Localize.Number.to_parts/2` plus the unit pattern text as
  # `:unit` parts, with surrounding whitespace tagged `:literal`,
  # matching ECMA-402 `formatToParts` for unit style.
  @spec to_parts(Localize.Unit.t(), Keyword.t()) ::
          {:ok, [%{type: atom(), value: String.t()}]} | {:error, Exception.t()}
  def to_parts(%Localize.Unit{value: value, name: name}, options \\ []) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    format = Keyword.get(options, :format, :long)

    with {:ok, language_tag} <- Localize.validate_locale(locale),
         {:ok, unit_data} <- load_unit_data(language_tag, format),
         {:ok, tokens} <- parts_pattern_tokens(unit_data, name, value, language_tag, options),
         {:ok, number_parts} <-
           Localize.Number.to_parts(value, Keyword.take(options, @number_format_options)) do
      parts =
        [number_parts]
        |> Localize.Substitution.substitute_parts(tokens, :unit)
        |> split_unit_whitespace()

      {:ok, parts}
    end
  end

  defp parts_pattern_tokens(unit_data, name, value, language_tag, options) do
    unit_name = normalize_unit_name(name)

    with unit_formats when is_map(unit_formats) <- find_unit_formats(unit_data, unit_name),
         plural = plural_form(value, language_tag),
         grammatical_case = Keyword.get(options, :grammatical_case, :nominative),
         tokens when is_list(tokens) <-
           pattern_tokens(resolve_pattern(unit_formats, grammatical_case, plural)) do
      {:ok, tokens}
    else
      _no_pattern ->
        {:error,
         Localize.InvalidValueError.exception(
           value: name,
           expected: "a unit with a direct CLDR pattern",
           context: "Localize.Unit.to_parts/2"
         )}
    end
  end

  # A CLDR unit pattern literal carries its spacing (" meters");
  # ECMA-402 tags the spacing as a separate :literal part.
  defp split_unit_whitespace(parts) do
    Enum.flat_map(parts, fn
      %{type: :unit, value: value} ->
        trimmed_leading = String.trim_leading(value)
        trimmed = String.trim_trailing(trimmed_leading)
        leading = binary_part(value, 0, byte_size(value) - byte_size(trimmed_leading))

        trailing =
          binary_part(
            trimmed_leading,
            byte_size(trimmed),
            byte_size(trimmed_leading) - byte_size(trimmed)
          )

        literal_part(leading) ++ unit_part(trimmed) ++ literal_part(trailing)

      part ->
        [part]
    end)
  end

  defp literal_part(""), do: []
  defp literal_part(whitespace), do: [%{type: :literal, value: whitespace}]

  defp unit_part(""), do: []
  defp unit_part(text), do: [%{type: :unit, value: text}]

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
            format_compound_or_fallback(value, name, parsed, unit_data, locale, options)

          unit_formats ->
            grammatical_case = Keyword.get(options, :grammatical_case, :nominative)
            # `:grammatical_gender` is accepted on the public API but only
            # meaningful for compound-unit patterns (`compound_unit_pattern`
            # keyed by gender). For simple units the gender of the unit
            # itself is fixed by CLDR data and the option has no effect —
            # same as cldr_units' simple-unit path.
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
    # `currency_code` arrives upper-cased and validated by
    # `Localize.Unit.validate_currency_codes/1` before parsing reaches
    # the formatter, so the atom is guaranteed to exist. Use
    # `existing_atom/1` defensively to keep this private function
    # DOS-safe against any future caller that bypasses validation.
    case Helpers.existing_atom(currency_code) do
      nil ->
        {:error, Localize.UnknownCurrencyError.exception(currency: currency_code)}

      currency_atom ->
        format_currency_unit_with_atom(
          value,
          currency_atom,
          denominator_units,
          unit_data,
          locale,
          options
        )
    end
  end

  defp format_currency_unit_with_atom(
         value,
         currency_atom,
         denominator_units,
         unit_data,
         locale,
         options
       ) do
    currency_options = Keyword.merge(options, currency: currency_atom, locale: locale)

    with {:ok, currency_string} <- format_number(value, currency_options) do
      case extract_denominator_parts(denominator_units) do
        {nil, nil} ->
          {:ok, currency_string}

        {count, denominator_base} ->
          format_per_denominator(
            currency_string,
            count,
            denominator_base,
            unit_data,
            value,
            locale
          )
      end
    end
  end

  # Composes a formatted numerator string ("$2.00", "2 feet") with the
  # denominator's per-unit pattern ("{0} per second"). Shared by the
  # currency-unit path and pattern-less per-compounds like "foot-per-second".
  defp format_per_denominator(
         numerator_string,
         count,
         denominator_base,
         unit_data,
         value,
         locale
       ) do
    denominator_name = normalize_unit_name(denominator_base)
    pattern = find_per_unit_pattern(unit_data, denominator_name, value, locale)
    nouns = if count, do: denominator_nouns(unit_data, denominator_name)
    format_per_unit(numerator_string, pattern, count, denominator_base, nouns)
  end

  defp format_per_unit(numerator_string, nil, count, denominator_base, nouns) do
    fallback_noun = String.replace(denominator_base, "-", " ")

    per_part =
      case {count, nouns} do
        {nil, _nouns} -> fallback_noun
        {count, {_singular, plural}} -> "#{count} #{plural}"
        {count, nil} -> "#{count} #{fallback_noun}"
      end

    {:ok, "#{numerator_string} per #{per_part}"}
  end

  defp format_per_unit(numerator_string, pattern, count, _denominator_base, nouns) do
    per_string =
      numerator_string
      |> Localize.Substitution.substitute(pattern)
      |> :erlang.iolist_to_binary()
      |> String.trim()

    cond do
      is_nil(count) ->
        {:ok, per_string}

      # With a denominator constant the unit noun is plural (compare
      # ICU: "liter-per-100-kilometer" → "per 100 kilometers"), so
      # replace the singular noun from the per-pattern with the count
      # and the plural noun.
      is_tuple(nouns) and String.contains?(per_string, elem(nouns, 0)) ->
        {singular, plural} = nouns
        {:ok, String.replace(per_string, singular, "#{count} #{plural}")}

      true ->
        # Insert the count before the denominator unit name in the pattern
        {:ok, String.replace(per_string, "per ", "per #{count} ")}
    end
  end

  # Extracts the singular and plural nouns for the denominator unit
  # from its CLDR nominative plural patterns, e.g. {"kilometer",
  # "kilometers"} for :kilometer in "en". Returns nil when the unit or
  # either plural form is not present in the locale data.
  defp denominator_nouns(unit_data, denominator_name) do
    with %{nominative: %{one: one_pattern, other: other_pattern}} <-
           find_unit_formats(unit_data, denominator_name),
         singular when is_binary(singular) <- pattern_noun(one_pattern),
         plural when is_binary(plural) <- pattern_noun(other_pattern) do
      {singular, plural}
    else
      _other -> nil
    end
  end

  defp pattern_noun(pattern) when is_list(pattern) do
    noun =
      pattern
      |> Enum.filter(&is_binary/1)
      |> Enum.join()
      |> String.trim()

    if noun == "", do: nil, else: noun
  end

  defp pattern_noun(_pattern), do: nil

  defp extract_denominator_parts([]), do: {nil, nil}

  defp extract_denominator_parts(units) do
    constant =
      Enum.find_value(units, fn
        {:constant, value} -> value
        _ -> nil
      end)

    single_unit_name =
      Enum.find_value(units, fn
        {:single_unit, keyword} -> denominator_unit_name(keyword)
        _ -> nil
      end)

    {constant, single_unit_name}
  end

  # Builds the full unit name for a denominator single unit, including
  # the SI prefix (kilo + meter → "kilometer") and the power
  # (square + kilometer → "square-kilometer"), so CLDR data lookups
  # resolve the actual unit rather than only its base.
  defp denominator_unit_name(keyword) do
    base = Keyword.fetch!(keyword, :base)
    prefix = Keyword.get(keyword, :prefix)
    power = Keyword.get(keyword, :power)

    prefixed = if prefix, do: "#{prefix}#{base}", else: base

    if power, do: "#{power}-#{prefixed}", else: prefixed
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

  # CLDR unit pattern resolution: grammatical-case, plural-form, and
  # pattern-shape fallbacks each contribute a branch.
  defp format_with_pattern(value, unit_formats, locale, grammatical_case, options) do
    plural = plural_form(value, locale)
    pattern = resolve_pattern(unit_formats, grammatical_case, plural)

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

  # Resolves the CLDR pattern for a grammatical case and plural
  # category, with nominative and :other fallbacks per CLDR.
  defp resolve_pattern(unit_formats, grammatical_case, plural) do
    case_forms =
      Map.get(unit_formats, grammatical_case) ||
        Map.get(unit_formats, :nominative) ||
        Map.get(unit_formats, :other)

    cond do
      is_map(case_forms) -> Map.get(case_forms, plural) || Map.get(case_forms, :other)
      is_list(case_forms) -> case_forms
      true -> nil
    end
  end

  # Normalizes any CLDR unit pattern shape to a Substitution token
  # list, or nil when there is no pattern.
  defp pattern_tokens([position, pattern_str])
       when is_integer(position) and is_binary(pattern_str) do
    unit_pattern_to_tokens(position, pattern_str)
  end

  defp pattern_tokens(tokens) when is_list(tokens), do: tokens
  defp pattern_tokens(pattern) when is_binary(pattern), do: [0, " " <> pattern]
  defp pattern_tokens(_other), do: nil

  # Converts the CLDR unit pattern [position, suffix] into a
  # Localize.Substitution-compatible token list.
  defp unit_pattern_to_tokens(0, pattern_str), do: [0, pattern_str]
  defp unit_pattern_to_tokens(1, pattern_str), do: [pattern_str, 0]
  defp unit_pattern_to_tokens(_, pattern_str), do: [0, pattern_str]

  # ── Number formatting ──────────────────────────────────────

  defp format_number(value, options) do
    number_options = Keyword.take(options, @number_format_options)
    Localize.Number.to_string(value, number_options)
  end

  # ── Plural form resolution ────────────────────────────────

  defp plural_form(value, locale) when is_number(value) do
    Localize.Number.PluralRule.Cardinal.plural_rule(value, locale)
  end

  # Decimals are passed through unconverted: the plural rule engine
  # computes the CLDR operands (including the visible-fraction operands
  # v, w, f and t) from the Decimal itself. Converting to float first
  # would lose those operands — Decimal "1" (v=0, :one in en) and
  # Decimal "1.0" (v=1, :other in en) both become the float 1.0.
  defp plural_form(%Decimal{} = value, locale) do
    Localize.Number.PluralRule.Cardinal.plural_rule(value, locale)
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

  # ── Compound per-unit formatting ───────────────────────────
  #
  # CLDR has direct patterns only for a small set of per-compounds
  # (e.g. "meter-per-second"). When a per-compound has no direct
  # pattern (e.g. "foot-per-second"), compose the formatted numerator
  # ("2 feet") with the denominator's per-unit pattern ("{0} per
  # second"), the same composition the currency-unit path uses.

  defp format_compound_or_fallback(value, name, parsed, unit_data, locale, options) do
    with {:ok, numerator_name, denominator_units} <- compound_per_parts(parsed),
         numerator_formats when not is_nil(numerator_formats) <-
           find_unit_formats(unit_data, normalize_unit_name(numerator_name)),
         {_count, denominator_base} when not is_nil(denominator_base) <-
           extract_denominator_parts(denominator_units) do
      format_compound_per_unit(
        value,
        numerator_formats,
        denominator_units,
        unit_data,
        locale,
        options
      )
    else
      _ -> format_custom_or_fallback(value, name, locale, options)
    end
  end

  defp format_compound_per_unit(
         value,
         numerator_formats,
         denominator_units,
         unit_data,
         locale,
         options
       ) do
    grammatical_case = Keyword.get(options, :grammatical_case, :nominative)

    with {:ok, numerator_string} <-
           format_with_pattern(value, numerator_formats, locale, grammatical_case, options) do
      {count, denominator_base} = extract_denominator_parts(denominator_units)
      format_per_denominator(numerator_string, count, denominator_base, unit_data, value, locale)
    end
  end

  # Extracts the single numerator unit name and the denominator units
  # from a parsed per-compound. Returns `:not_compound` for anything
  # other than a single-unit numerator with a non-empty denominator.
  defp compound_per_parts({:unit, keyword}) do
    numerator = Keyword.get(keyword, :numerator, [])
    denominator = Keyword.get(keyword, :denominator, [])

    case {numerator, denominator} do
      {[{:single_unit, kw}], [_ | _]} ->
        {:ok, denominator_unit_name(kw), denominator}

      _ ->
        :not_compound
    end
  end

  defp compound_per_parts(_parsed), do: :not_compound

  # ── Custom unit formatting ─────────────────────────────────
  #
  # When a unit is not found in the CLDR locale data, check the
  # custom registry for display patterns before falling back to
  # the bare "value name" format.

  defp format_custom_or_fallback(value, name, locale, options) do
    style = Keyword.get(options, :format, Keyword.get(options, :style, :long))

    with {:ok, locale_id} <- extract_locale_id(locale) do
      case Localize.Unit.CustomRegistry.get(name) do
        %{display: display} when is_map(display) ->
          locale_display = Map.get(display, locale_id, %{})
          style_display = Map.get(locale_display, style, %{})
          format_custom_display(style_display, value, name, locale, options)

        _ ->
          format_fallback(value, name, options)
      end
    end
  end

  defp format_custom_display(patterns, value, _name, locale, options)
       when map_size(patterns) > 0 do
    format_custom_patterns(value, patterns, locale, options)
  end

  defp format_custom_display(_patterns, value, name, _locale, options) do
    format_fallback(value, name, options)
  end

  defp format_custom_patterns(value, patterns, locale, options) do
    plural = plural_form(value, locale)

    pattern =
      Map.get(patterns, plural) ||
        Map.get(patterns, :other) ||
        "{0} #{Map.get(patterns, :display_name, "unknown")}"

    with {:ok, number_str} <- format_number(value, options) do
      formatted = String.replace(pattern, "{0}", number_str)
      {:ok, formatted}
    end
  end

  defp extract_locale_id(locale) do
    Localize.Locale.cldr_locale_id_from(locale)
  end

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

  # The NIF backend validates the locale through the same canonical
  # path as the Elixir backend (`Localize.validate_locale/1`) and hands
  # ICU the canonical BCP 47 string, so both backends resolve aliases,
  # likely subtags and `-u-` extensions identically.
  defp validated_locale_string(locale) do
    with {:ok, language_tag} <- Localize.validate_locale(locale) do
      {:ok, Localize.LanguageTag.to_string(language_tag)}
    end
  end
end
