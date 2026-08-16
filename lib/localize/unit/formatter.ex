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
         plural = plural_form(value, language_tag, options),
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
    nouns = denominator_nouns(unit_data, denominator_name)

    # A precomposed `per_unit_pattern` states "per one X" (TR35), so it
    # cannot carry a denominator count: "{0}/d" has nowhere to put the
    # "30" of "per-30-day". When the denominator has a constant, compose
    # the counted denominator through the locale's `compound.per`
    # pattern instead, exactly as a denominator with no per-pattern does.
    if is_nil(pattern) or not is_nil(count) do
      compose_per_compound(numerator_string, count, denominator_base, nouns, unit_data)
    else
      format_per_unit(numerator_string, pattern)
    end
  end

  # Composes a per-compound that has no precomposed `per_unit_pattern`
  # for its denominator. Combines the formatted numerator with the
  # localized denominator noun using the locale's `compound.per` pattern
  # (`{0} per {1}`, `{0} par {1}`, `{0} na {1}`, …). Per the CLDR "per"
  # derivation the denominator is singular nominative, unless a
  # denominator constant (as in "liter-per-100-kilometer") makes it a
  # counted plural. Falls back to a bare "per" only when the locale has
  # no `compound.per` pattern at all.
  defp compose_per_compound(numerator_string, count, denominator_base, nouns, unit_data) do
    denominator = per_denominator_display(count, nouns, denominator_base)

    case per_compound_pattern_tokens(unit_data) do
      nil ->
        {:ok, "#{numerator_string} per #{denominator}"}

      per_tokens ->
        {:ok, apply_compound_pattern(numerator_string, denominator, per_tokens)}
    end
  end

  defp per_denominator_display(count, nouns, denominator_base) do
    fallback_noun = String.replace(denominator_base, "-", " ")

    case {count, nouns} do
      {nil, {singular, _plural}} -> singular
      {nil, nil} -> fallback_noun
      {count, {_singular, plural}} -> "#{count} #{plural}"
      {count, nil} -> "#{count} #{fallback_noun}"
    end
  end

  defp per_compound_pattern_tokens(unit_data) do
    case get_in(unit_data, [:compound, :per, :compound_unit_pattern]) do
      tokens when is_list(tokens) -> tokens
      _other -> nil
    end
  end

  # Substitutes the formatted numerator into the denominator's
  # precomposed `per_unit_pattern` ("{0} per second", "{0}/d"). Only
  # reached for an uncounted denominator — a counted one is composed
  # through `compose_per_compound/5` instead.
  defp format_per_unit(numerator_string, pattern) do
    per_string =
      numerator_string
      |> Localize.Substitution.substitute(pattern)
      |> :erlang.iolist_to_binary()
      |> String.trim()

    {:ok, per_string}
  end

  # Extracts the singular and plural nouns for the denominator unit
  # from its CLDR nominative plural patterns, e.g. {"kilometer",
  # "kilometers"} for :kilometer in "en". Locales without a plural
  # distinction (zh, ja) carry only an `:other` form, which is reused
  # for the singular. Returns nil when the unit has no nominative
  # `:other` form in the locale data.
  defp denominator_nouns(unit_data, denominator_name) do
    with %{nominative: %{other: other_pattern} = nominative} <-
           find_unit_formats(unit_data, denominator_name),
         plural when is_binary(plural) <- pattern_noun(other_pattern) do
      singular = pattern_noun(Map.get(nominative, :one)) || plural
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
    plural = plural_form(value, locale, options)
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

  # TR35 defines the plural operands over the *source number* — "the visual
  # appearance of the digits of the result" — so the category follows what the
  # reader ends up seeing, not what was passed in. Under the default pattern
  # the float 1.0 renders as "1" (v=0, :one in English), while the integer 1
  # with `fractional_digits: 2` renders as "1.00" (v=2, :other). Selecting on
  # the input value gets both of those backwards, in opposite directions.
  defp plural_form(value, locale, options) when is_number(value) or is_struct(value, Decimal) do
    value
    |> source_number(options)
    |> Localize.Number.PluralRule.Cardinal.plural_rule(locale)
  end

  defp plural_form(_value, _locale, _options), do: :other

  # The value rescaled to the fraction digits that will actually be printed,
  # which is what carries the v, w, f and t operands.
  #
  # The digit count comes from the formatter rather than from a second reading
  # of the format metadata, so rounding, significant digits and `:round_nearest`
  # cannot drift away from what is displayed. Only the count is taken: the
  # digits themselves are localized — Devanagari under `hi-u-nu-deva` — and
  # rescaling the original value supplies the rest of the operands without
  # having to transliterate them back.
  defp source_number(value, options) do
    with {:ok, parts} <-
           Localize.Number.to_parts(value, Keyword.take(options, @number_format_options)),
         %Decimal{} = decimal <- to_decimal(value) do
      Decimal.round(decimal, fraction_digit_count(parts))
    else
      _other -> value
    end
  end

  defp fraction_digit_count(parts) do
    case Enum.find(parts, &(&1.type == :fraction)) do
      %{value: fraction} when is_binary(fraction) -> String.length(fraction)
      _other -> 0
    end
  end

  defp to_decimal(%Decimal{coef: coef} = value) when is_integer(coef), do: value
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp to_decimal(value) when is_float(value), do: Decimal.from_float(value)

  # NaN and infinity have no digits to count, and `Decimal.round/2` raises on
  # them. They fall back to the plural rule's own handling of the raw value.
  defp to_decimal(_non_finite), do: nil

  # ── Unit name resolution ───────────────────────────────────

  defp find_unit_formats(unit_data, unit_name) do
    direct = direct_unit_formats(unit_data, unit_name)

    if formattable_unit_formats?(direct) do
      direct
    else
      # A metadata-only entry (some locales carry a bare
      # `%{gender: ...}` for units like "day-person" with no patterns of
      # their own) counts as a miss, so the suffix fallback can resolve
      # the base unit's display.
      suffixed_unit_formats(unit_data, unit_name) || direct
    end
  end

  # A unit-formats map is usable only if it carries a `:display_name` or
  # at least one grammatical-case pattern map (`:nominative`, …); a
  # gender-only entry has neither.
  defp formattable_unit_formats?(%{} = formats) do
    Map.has_key?(formats, :display_name) or Enum.any?(Map.values(formats), &is_map/1)
  end

  defp formattable_unit_formats?(_other), do: false

  defp direct_unit_formats(unit_data, unit_name) do
    unit_atom = safe_to_atom(unit_name)

    # Search through all categories for this unit name
    Enum.find_value(unit_data, fn
      {_category, units} when is_map(units) ->
        Map.get(units, unit_atom) || Map.get(units, unit_name)

      _ ->
        nil
    end)
  end

  # CLDR marks components such as "person" as unit-id suffixes
  # (`unitIdComponent type="suffix"`). Units like "year-person"
  # (person-years) carry no display data of their own and are shown as
  # their base unit ("year" → "years"), matching ICU. When a direct
  # lookup misses, strip a trailing recognized suffix component and retry
  # against the base unit — which only resolves when that base is itself
  # a real unit, so it is a no-op for identifiers without display data.
  defp suffixed_unit_formats(unit_data, unit_name) do
    case strip_suffix_component(unit_name) do
      nil -> nil
      base_name -> direct_unit_formats(unit_data, base_name)
    end
  end

  defp strip_suffix_component(unit_name) do
    Enum.find_value(Localize.Unit.Data.suffix_components(), fn suffix ->
      suffixed = "_" <> suffix

      if unit_name != suffixed and String.ends_with?(unit_name, suffixed) do
        String.replace_suffix(unit_name, suffixed, "")
      end
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
      _ -> format_times_or_fallback(value, name, parsed, unit_data, locale, options)
    end
  end

  # A "times" compound is a product of two or more single units with no
  # denominator (e.g. "tonne-kilometer"). CLDR has direct patterns only
  # for a subset (e.g. "newton-meter"); the rest are composed at runtime
  # from the component nouns and the locale's `compound.times` pattern.
  # When composition is not possible (a component has no locale pattern,
  # or the times pattern is absent) fall back to the custom-unit / raw
  # path so nothing regresses to an error.
  defp format_times_or_fallback(value, name, parsed, unit_data, locale, options) do
    with {:ok, single_units} <- compound_times_parts(parsed),
         {:ok, string} <- format_times_compound(value, single_units, unit_data, locale, options) do
      {:ok, string}
    else
      _ -> format_prefixed_or_fallback(value, name, parsed, unit_data, locale, options)
    end
  end

  # An SI-prefixed unit with no precomposed CLDR pattern of its own
  # ("megajoule") composes its display from the prefix pattern and the
  # base unit's noun ("mega" + "joules" → "megajoules", "M" + "J" → "MJ"),
  # per the CLDR `si_prefix` step of `patternTimes`. Prefixed units that
  # do have their own pattern ("kilojoule", "milligram") never reach here.
  defp format_prefixed_or_fallback(value, name, parsed, unit_data, locale, options) do
    with {:ok, prefix, base} <- prefixed_single_unit(parsed),
         {:ok, string} <- format_prefixed_unit(value, prefix, base, unit_data, locale, options) do
      {:ok, string}
    else
      _ -> format_custom_or_fallback(value, name, locale, options)
    end
  end

  # Extracts the `{prefix, base}` of a single prefixed unit with no power
  # and no denominator ("megajoule"); anything else is `:not_prefixed`.
  defp prefixed_single_unit({:unit, keyword}) do
    numerator = Keyword.get(keyword, :numerator, [])
    denominator = Keyword.get(keyword, :denominator, [])

    case {numerator, denominator} do
      {[{:single_unit, single}], []} ->
        prefix = Keyword.get(single, :prefix)
        power = Keyword.get(single, :power)
        base = Keyword.get(single, :base)

        if not is_nil(prefix) and is_nil(power) and is_binary(base) do
          {:ok, prefix, base}
        else
          :not_prefixed
        end

      _ ->
        :not_prefixed
    end
  end

  defp prefixed_single_unit(_parsed), do: :not_prefixed

  defp format_prefixed_unit(value, prefix, base, unit_data, locale, options) do
    grammatical_case = Keyword.get(options, :grammatical_case, :nominative)
    count_plural = plural_form(value, locale, options)

    with prefix_tokens when is_list(prefix_tokens) <- si_prefix_pattern_tokens(unit_data, prefix),
         base_formats when not is_nil(base_formats) <-
           find_unit_formats(unit_data, normalize_unit_name(base)),
         base_pattern when is_list(base_pattern) <-
           resolve_pattern(base_formats, grammatical_case, count_plural),
         base_noun when is_binary(base_noun) <- pattern_noun(base_pattern) do
      style = Keyword.get(options, :format, :long)
      prefixed_noun = apply_prefix_pattern(prefix_tokens, base_noun, style)
      final_tokens = splice_combined_noun(pattern_tokens(base_pattern), base_noun, prefixed_noun)

      with {:ok, number_str} <- format_number(value, options) do
        result = Localize.Substitution.substitute(number_str, final_tokens)
        {:ok, result |> :erlang.iolist_to_binary() |> String.trim()}
      end
    else
      _ -> :error
    end
  end

  # Prepends the SI prefix to the base noun using the prefix's
  # single-placeholder pattern (`["M", 0]` → "M" <> noun). Applies CLDR
  # `combineLowercasing`: for the long form with a space-free prefix, the
  # base noun is lowercased so a capitalising language composes correctly
  # ("Mega" + "Joule" → "Megajoule", not "MegaJoule").
  defp apply_prefix_pattern(prefix_tokens, noun, style) do
    prefix_literal = prefix_tokens |> Enum.filter(&is_binary/1) |> Enum.join()

    noun =
      if style == :long and prefix_literal != "" and not String.contains?(prefix_literal, " ") do
        String.downcase(noun)
      else
        noun
      end

    Enum.map_join(prefix_tokens, "", fn
      0 -> noun
      literal when is_binary(literal) -> literal
      _other -> ""
    end)
  end

  defp si_prefix_pattern_tokens(unit_data, prefix) do
    with key when is_binary(key) <- si_prefix_compound_key(prefix),
         %{unit_prefix_pattern: pattern} <- get_in(unit_data, [:compound, safe_to_atom(key)]),
         tokens when is_list(tokens) <- pattern do
      tokens
    else
      _other -> nil
    end
  end

  # Maps an SI prefix atom (`:mega`, `:nano`) to the CLDR `compound` key
  # that holds its `unit_prefix_pattern` — the power of ten with a leading
  # `_` for negative exponents (`10p6` for mega, `10p_9` for nano). Binary
  # prefixes (kibi, mebi) have no `power10` and are left uncomposed.
  defp si_prefix_compound_key(prefix) do
    prefix_string = Atom.to_string(prefix)

    Enum.find_value(Localize.Unit.Data.si_prefix_data(), fn
      %{type: ^prefix_string, power10: "-" <> magnitude} -> "10p_" <> magnitude
      %{type: ^prefix_string, power10: power10} when power10 != "" -> "10p" <> power10
      _other -> nil
    end)
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

  # ── Compound times-unit formatting ─────────────────────────
  #
  # Composes the localized name of a product unit ("tonne-kilometer")
  # per the CLDR algorithm (TR35 "Compound Units", `patternTimes`):
  # each component is formatted to its noun in the grammatically-derived
  # plural/case, and the nouns are joined with the locale's
  # `compound.times` pattern. The count is carried by the trailing
  # component (and, in French, by every component); the number is then
  # placed using the leading component's own pattern so its position and
  # spacing match a simple unit in that locale.

  # Extracts the product's single units, or `:not_compound` for anything
  # that is not a two-or-more single-unit numerator with an empty
  # denominator (a `:constant` factor, or a per-compound, is excluded).
  defp compound_times_parts({:unit, keyword}) do
    numerator = Keyword.get(keyword, :numerator, [])
    denominator = Keyword.get(keyword, :denominator, [])

    case {numerator, denominator} do
      {[_, _ | _] = single_units, []} ->
        if Enum.all?(single_units, &match?({:single_unit, _keyword}, &1)) do
          {:ok, single_units}
        else
          :not_compound
        end

      _ ->
        :not_compound
    end
  end

  defp compound_times_parts(_parsed), do: :not_compound

  defp format_times_compound(value, single_units, unit_data, locale, options) do
    grammatical_case = Keyword.get(options, :grammatical_case, :nominative)
    count_plural = plural_form(value, locale, options)

    # CLDR derives each component's plural and case from the compound as a
    # whole (grammaticalFeatures.xml `deriveComponent structure="times"`):
    # value0 governs every component but the last, value1 the last, and a
    # `:compound` derivation means "carry the compound's own category". The
    # root default renders leading components singular so the trailing one
    # carries the count ("5 newton-meters"); French pluralizes every
    # component ("5 tonnes-kilomètres"). The table is loaded from CLDR data.
    {{plural0, plural1}, {case0, case1}} = times_derivations(locale)

    leading_plural = resolve_derived_category(plural0, count_plural)
    leading_case = resolve_derived_category(case0, grammatical_case)
    trailing_plural = resolve_derived_category(plural1, count_plural)
    trailing_case = resolve_derived_category(case1, grammatical_case)

    {leading_units, [trailing_unit]} = Enum.split(single_units, -1)

    specs =
      Enum.map(leading_units, &{&1, leading_case, leading_plural}) ++
        [{trailing_unit, trailing_case, trailing_plural}]

    with times_tokens when is_list(times_tokens) <- times_pattern_tokens(unit_data),
         {:ok, [leading_pattern | _] = patterns} <- resolve_times_components(specs, unit_data),
         nouns = Enum.map(patterns, &pattern_noun/1),
         true <- Enum.all?(nouns, &is_binary/1) do
      combined_noun = combine_times_nouns(nouns, times_tokens)

      final_tokens =
        splice_combined_noun(pattern_tokens(leading_pattern), hd(nouns), combined_noun)

      with {:ok, number_str} <- format_number(value, options) do
        result = Localize.Substitution.substitute(number_str, final_tokens)
        {:ok, result |> :erlang.iolist_to_binary() |> String.trim()}
      end
    else
      _ -> :error
    end
  end

  # Resolves each `{single_unit, case, plural}` spec to its CLDR pattern,
  # or `:error` if any component has no pattern in the locale (an exotic
  # component the composed path cannot name).
  defp resolve_times_components(specs, unit_data) do
    patterns =
      Enum.map(specs, fn {{:single_unit, keyword}, grammatical_case, plural} ->
        unit_name = normalize_unit_name(denominator_unit_name(keyword))

        case find_unit_formats(unit_data, unit_name) do
          nil -> nil
          formats -> resolve_pattern(formats, grammatical_case, plural)
        end
      end)

    if Enum.all?(patterns, &is_list/1), do: {:ok, patterns}, else: :error
  end

  # Joins component nouns left-to-right with the two-placeholder
  # `compound.times` pattern (`[0, "⋅", 1]`), matching CLDR's
  # left-associative combination for three-or-more-unit products.
  defp combine_times_nouns([first | rest], times_tokens) do
    Enum.reduce(rest, first, &apply_compound_pattern(&2, &1, times_tokens))
  end

  # Substitutes two operands into a two-placeholder compound pattern —
  # `compound.times` (`[0, "⋅", 1]`) or `compound.per` (`[0, " per ", 1]`).
  defp apply_compound_pattern(left, right, tokens) do
    Enum.map_join(tokens, "", fn
      0 -> left
      1 -> right
      literal when is_binary(literal) -> literal
      _other -> ""
    end)
  end

  # Substitutes the combined product noun for the leading component's own
  # noun inside the leading pattern, so the number keeps that component's
  # placeholder position and spacing.
  defp splice_combined_noun(leading_tokens, leading_noun, combined_noun) do
    Enum.map(leading_tokens, fn
      token when is_binary(token) ->
        String.replace(token, leading_noun, combined_noun, global: false)

      token ->
        token
    end)
  end

  defp times_pattern_tokens(unit_data) do
    case get_in(unit_data, [:compound, :times, :compound_unit_pattern]) do
      tokens when is_list(tokens) -> tokens
      _other -> nil
    end
  end

  # The `{plural, case}` derivations for a "times" compound in the given
  # locale, each a `{value0, value1}` tuple. Looks up the locale's base
  # language in the CLDR derivation table, falling back to `"root"` and
  # then to the hard-coded root defaults if the table is unavailable.
  defp times_derivations(locale) do
    table = Localize.SupplementalData.unit_grammatical_derivations()
    language_table = Map.get(table, times_language(locale)) || Map.get(table, "root") || %{}

    {
      get_in(language_table, [:plural, :times]) || {:one, :compound},
      get_in(language_table, [:case, :times]) || {:nominative, :compound}
    }
  end

  # A `:compound` derivation resolves to the compound's own category (the
  # count's plural category or the requested case); any other value is a
  # fixed category used verbatim.
  defp resolve_derived_category(:compound, compound_category), do: compound_category
  defp resolve_derived_category(category, _compound_category), do: category

  defp times_language(%Localize.LanguageTag{language: language}), do: Atom.to_string(language)

  # ── Custom unit formatting ─────────────────────────────────
  #
  # When a unit is not found in the CLDR locale data, check the
  # custom registry for display patterns before falling back to
  # the bare "value name" format.

  defp format_custom_or_fallback(value, name, locale, options) do
    style = Keyword.get(options, :format, :long)

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
    plural = plural_form(value, locale, options)

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
