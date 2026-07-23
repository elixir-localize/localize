defmodule Localize.Number.Formatter.Decimal do
  @moduledoc false

  # Formats a number according to a locale-specific format pattern.
  #
  # This is the core number formatting engine. It takes a number,
  # parses it according to the format metadata, applies grouping,
  # rounding, transliteration, and assembles the final string.

  alias Localize.Number.Format.Compiler
  alias Localize.Number.Format.Options
  alias Localize.Utils.{Digits, Math}

  @empty_string ""

  # Compile-time pattern placeholders and the zero-width currency
  # sentinel, defined ahead of every function per house style.
  @group_separator Compiler.placeholder(:group)
  @decimal_separator Compiler.placeholder(:decimal)
  @exponent_separator Compiler.placeholder(:exponent)
  @exponent_sign Compiler.placeholder(:exponent_sign)
  @minus_placeholder Compiler.placeholder(:minus)
  @nbsp "\u200b"

  # # to_string/3
  # Formats a number using a format string and validated options.
  #
  # ### Arguments
  # * `number` is an integer, float, Decimal, or string.
  # * `format` is a format pattern string.
  # * `options` is a `Localize.Number.Format.Options.t()`.
  #
  # ### Returns
  # * `{:ok, formatted_string}` or `{:error, exception}`.
  @spec to_string(number() | Decimal.t() | String.t(), String.t(), Options.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def to_string(number, format, %Options{} = options) when is_binary(format) do
    case metadata(format) do
      {:ok, meta} ->
        meta = update_meta(meta, number, options)
        result = do_to_string(number, meta, options)
        {:ok, result}

      {:error, reason} ->
        {:error,
         Localize.InvalidValueError.exception(
           value: format,
           expected: "a valid number format",
           context: reason
         )}
    end
  end

  # # to_parts/3
  # Formats a number into a list of typed parts per ECMA-402
  # `formatToParts`: `[%{type: atom(), value: String.t()}]`. The
  # pipeline mirrors `to_string/3` exactly — same metadata, same
  # rounding, same grouping — but the assembly stage emits tagged
  # segments instead of a concatenated binary.
  @spec to_parts(number() | Decimal.t(), String.t(), Options.t()) ::
          {:ok, [%{type: atom(), value: String.t()}]} | {:error, Exception.t()}
  def to_parts(number, format, %Options{} = options) when is_binary(format) do
    case metadata(format) do
      {:ok, meta} ->
        meta = update_meta(meta, number, options)
        {:ok, do_to_parts(number, meta, options)}

      {:error, reason} ->
        {:error,
         Localize.InvalidValueError.exception(
           value: format,
           expected: "a valid number format",
           context: reason
         )}
    end
  end

  # # metadata/1
  # Returns the parsed metadata for a format string.
  @doc false
  def metadata(format) when is_binary(format) do
    key = {:localize, :number_format_meta, format}

    case Localize.FormatCache.lookup(key) do
      {:ok, meta} ->
        {:ok, meta}

      :miss ->
        case Compiler.format_to_metadata(format) do
          {:ok, meta} ->
            Localize.FormatCache.store(key, meta)
            {:ok, meta}

          error ->
            error
        end
    end
  end

  @doc false
  def metadata!(format) do
    case metadata(format) do
      {:ok, meta} -> meta
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc false
  def update_meta(meta, number, options) do
    options = resolve_rounding_priority(options, number)

    meta
    |> apply_significant_digit_options(options)
    |> adjust_fraction_for_currency(options.currency, options.currency_digits)
    |> adjust_fraction_for_significant_digits(number)
    |> adjust_for_fractional_digits(options)
    |> adjust_for_integer_digits(options.maximum_integer_digits)
    |> adjust_for_minimum_integer_digits(options.minimum_integer_digits)
    |> adjust_for_round_nearest(options.round_nearest)
    |> Map.put(:number, number)
  end

  # Caller-supplied `:minimum_significant_digits` /
  # `:maximum_significant_digits` override whatever the format
  # pattern's `@@##` metadata produced. Per TR35 / ECMA-402,
  # significant-digit settings take precedence over fractional-
  # digit settings — this is enforced naturally because the
  # formatter applies `round_to_significant_digits/2` before any
  # fractional-digit rounding, and `adjust_fraction_for_significant_digits/2`
  # widens the fractional-digit envelope to `%{max: 10, min: 1}`
  # whenever significant digits are active.
  #
  # When only one of the two options is set, the other defaults to
  # the same value (single-digit precision) for `:minimum_significant_digits`
  # and to `21` (the ECMA-402 upper bound) for unset
  # `:maximum_significant_digits`. When neither is set, the meta
  # struct is unchanged.
  defp apply_significant_digit_options(meta, options) do
    min = options.minimum_significant_digits
    max = options.maximum_significant_digits

    if is_nil(min) and is_nil(max) do
      meta
    else
      resolved_min = min || 1
      resolved_max = max || 21
      %{meta | significant_digits: %{min: resolved_min, max: resolved_max}}
    end
  end

  # ECMA-402 `roundingPriority`. Meaningful only when both
  # significant-digit and fraction-digit bounds are present. For
  # `:more_precision` / `:less_precision` the spec compares the
  # rounding position each bound implies for this value —
  # significant digits round at `magnitude - (max_sd - 1)`,
  # fraction digits at `-max_fd` — and the winner's bounds apply
  # while the loser's are discarded. Ties go to the significant-
  # digit bounds, matching `Intl.NumberFormat`.
  defp resolve_rounding_priority(%{rounding_priority: priority} = options, number)
       when priority in [:more_precision, :less_precision] do
    significant? =
      not is_nil(options.minimum_significant_digits) or
        not is_nil(options.maximum_significant_digits)

    max_fd = options.max_fractional_digits || options.fractional_digits

    fractional? = not is_nil(max_fd) or not is_nil(options.min_fractional_digits)

    if significant? and fractional? do
      apply_rounding_priority(options, number, priority, max_fd)
    else
      options
    end
  end

  # The default (`nil` / `:auto`): per ECMA-402
  # SetNumberFormatDigitOptions, a significant-digit bound causes
  # the fraction-digit bounds to be ignored entirely — significant
  # digits win outright, not merely round first.
  defp resolve_rounding_priority(options, _number) do
    significant? =
      not is_nil(options.minimum_significant_digits) or
        not is_nil(options.maximum_significant_digits)

    if significant? do
      %{
        options
        | fractional_digits: nil,
          min_fractional_digits: nil,
          max_fractional_digits: nil
      }
    else
      options
    end
  end

  defp apply_rounding_priority(options, number, priority, max_fd) do
    max_sd = options.maximum_significant_digits || 21
    resolved_max_fd = max_fd || max(options.min_fractional_digits || 0, 3)

    significant_position = magnitude(number) - (max_sd - 1)
    fractional_position = -resolved_max_fd

    significant_wins? =
      case priority do
        :more_precision -> significant_position <= fractional_position
        :less_precision -> significant_position >= fractional_position
      end

    if significant_wins? do
      %{
        options
        | fractional_digits: nil,
          min_fractional_digits: nil,
          max_fractional_digits: nil
      }
    else
      %{options | minimum_significant_digits: nil, maximum_significant_digits: nil}
    end
  end

  # The exponent of the most significant digit: floor(log10(|x|)),
  # with 0 for zero and non-finite values (rounding does not apply
  # to them).
  defp magnitude(%Decimal{coef: coef}) when coef in [:NaN, :inf], do: 0

  defp magnitude(%Decimal{coef: 0}), do: 0

  defp magnitude(%Decimal{coef: coef, exp: exp}) when is_integer(coef) do
    Integer.digits(coef) |> length() |> Kernel.+(exp - 1)
  end

  defp magnitude(number) when is_number(number) do
    absolute = abs(number)

    cond do
      absolute == 0 -> 0
      absolute >= 1 -> Digits.number_of_integer_digits(absolute) - 1
      true -> floor(:math.log10(absolute))
    end
  end

  # ── Core formatting pipeline ──────────────────────────────

  defp do_to_string(%Decimal{coef: :NaN}, meta, options) do
    options = resolve_sign_display_for_nan(options)

    options.symbols.nan
    |> assemble_format(meta, options)
  end

  defp do_to_string(%Decimal{coef: :inf} = number, meta, options) do
    options = resolve_sign_display(options, number, false)

    options.symbols.infinity
    |> assemble_format(meta, options)
  end

  defp do_to_string(string, meta, options) when is_binary(string) do
    assemble_format(string, meta, options)
  end

  defp do_to_string(number, %{integer_digits: _} = meta, options) do
    digit_tuple =
      number
      |> absolute_value()
      |> multiply_by_factor(meta)
      |> round_to_significant_digits(meta)
      |> round_to_nearest(meta, options)
      |> set_exponent(meta)
      |> round_fractional_digits(meta, options)
      |> output_to_tuple()
      |> adjust_leading_zeros(meta)
      |> adjust_trailing_zeros(meta, options)
      |> set_max_integer_digits(meta)

    options = resolve_sign_display(options, number, rounds_to_zero?(digit_tuple))

    digit_tuple
    |> apply_grouping(meta, options)
    |> reassemble_number_string(meta, options)
    |> transliterate_string(options)
    |> assemble_format(meta, options)
  end

  defp do_to_string(number, meta, options) do
    assemble_format(number, meta, options)
  end

  # ── Parts pipeline ─────────────────────────────────────────

  # Mirrors `do_to_string/3`: the digit pipeline is identical up to
  # `apply_grouping/3`; the number body is then split into typed
  # segments instead of fused into a binary. The plain formatted
  # number string is still computed — the currency-spacing
  # predicates, padding width, and the zero-suppressed minus all
  # depend on it.
  defp do_to_parts(%Decimal{coef: :NaN}, meta, options) do
    options = resolve_sign_display_for_nan(options)
    body = [%{type: :nan, value: options.symbols.nan}]
    walk_format_parts(body, options.symbols.nan, meta, options)
  end

  defp do_to_parts(%Decimal{coef: :inf} = number, meta, options) do
    options = resolve_sign_display(options, number, false)
    body = [%{type: :infinity, value: options.symbols.infinity}]
    walk_format_parts(body, options.symbols.infinity, meta, options)
  end

  defp do_to_parts(number, %{integer_digits: _} = meta, options) do
    digit_tuple =
      number
      |> absolute_value()
      |> multiply_by_factor(meta)
      |> round_to_significant_digits(meta)
      |> round_to_nearest(meta, options)
      |> set_exponent(meta)
      |> round_fractional_digits(meta, options)
      |> output_to_tuple()
      |> adjust_leading_zeros(meta)
      |> adjust_trailing_zeros(meta, options)
      |> set_max_integer_digits(meta)

    options = resolve_sign_display(options, number, rounds_to_zero?(digit_tuple))
    grouped_tuple = apply_grouping(digit_tuple, meta, options)

    number_string =
      grouped_tuple
      |> reassemble_number_string(meta, options)
      |> transliterate_string(options)

    body = number_body_parts(grouped_tuple, meta, options)
    walk_format_parts(body, number_string, meta, options)
  end

  defp number_body_parts({_sign, integer, fraction, exponent_sign, exponent}, meta, options) do
    digit_map = parts_transliteration_map(options)
    group_symbol = parts_symbol(options, :group, @group_separator)
    decimal_symbol = parts_symbol(options, :decimal, @decimal_separator)

    integer = if integer == [], do: [?0], else: integer
    integer_parts = split_grouped_digits(integer, :integer, group_symbol, digit_map)

    fraction_parts =
      if fraction == [] do
        []
      else
        [
          %{type: :decimal, value: decimal_symbol}
          | split_grouped_digits(fraction, :fraction, group_symbol, digit_map)
        ]
      end

    integer_parts ++ fraction_parts ++ exponent_parts(exponent_sign, exponent, meta, options)
  end

  # The grouped charlists interleave digit codepoints with the
  # group-separator placeholder; each digit run becomes one part.
  defp split_grouped_digits(grouped, part_type, group_symbol, digit_map) do
    grouped
    |> List.flatten()
    |> Enum.chunk_by(&(&1 == @group_separator or &1 == [@group_separator]))
    |> Enum.map(fn
      [sep | _] = chunk when sep == @group_separator or not is_integer(sep) ->
        List.duplicate(%{type: :group, value: group_symbol}, length(chunk))

      digits ->
        [%{type: part_type, value: transliterate_part_value(List.to_string(digits), digit_map)}]
    end)
    |> List.flatten()
  end

  defp exponent_parts(_exponent_sign, _exponent, %{exponent_digits: 0}, _options), do: []

  defp exponent_parts(exponent_sign, exponent, meta, options) do
    digit_map = parts_transliteration_map(options)

    digits =
      exponent
      |> List.to_string()
      |> String.pad_leading(meta.exponent_digits, "0")
      |> transliterate_part_value(digit_map)

    sign_parts =
      cond do
        exponent_sign < 0 ->
          [
            %{
              type: :exponent_minus_sign,
              value: IO.iodata_to_binary(exponent_minus_symbol(options))
            }
          ]

        meta.exponent_sign ->
          [
            %{
              type: :exponent_plus_sign,
              value: IO.iodata_to_binary(exponent_plus_symbol(options))
            }
          ]

        true ->
          []
      end

    separator = IO.iodata_to_binary(exponent_separator_symbol(options))

    [%{type: :exponent_separator, value: separator}] ++
      sign_parts ++ [%{type: :exponent_integer, value: digits}]
  end

  defp parts_symbol(%{symbols: nil}, _kind, placeholder), do: placeholder

  defp parts_symbol(%{symbols: symbols}, kind, placeholder) do
    extract_symbol(Map.fetch!(symbols, kind)) || placeholder
  end

  defp parts_transliteration_map(%{number_system: system})
       when system not in [nil, :latn] do
    with {:ok, digits} <- Localize.Number.System.number_system_digits(system),
         {:ok, latn_digits} <- Localize.Number.System.number_system_digits(:latn) do
      Localize.Number.System.generate_transliteration_map(latn_digits, digits)
    else
      _ -> nil
    end
  end

  defp parts_transliteration_map(_options), do: nil

  defp transliterate_part_value(value, nil), do: value

  defp transliterate_part_value(value, digit_map) do
    Localize.Number.Transliterate.transliterate_digits(value, digit_map)
  end

  # The parts counterpart of `assemble_parts/5`: walks the same
  # affix token list, emitting typed parts. Part type names follow
  # ECMA-402 `formatToParts` in snake_case (`:minus_sign`,
  # `:percent_sign`, `:currency`, …); currency spacing and padding
  # surface as `:literal` parts, as in `Intl.NumberFormat`.
  defp walk_format_parts(body_parts, number_string, meta, options) do
    tokens = pattern_parts(meta.format, options.pattern)

    tokens
    |> walk_tokens(body_parts, number_string, meta, options)
    |> List.flatten()
    |> Enum.reject(&(&1.value in [nil, ""]))
  end

  defp walk_tokens([], _body, _number_string, _meta, _options), do: []

  defp walk_tokens(
         [{:format, _}, {:currency, _type} | rest],
         body,
         number_string,
         meta,
         %{currency_spacing: spacing} = options
       )
       when not is_nil(spacing) do
    symbol = options.currency_symbol
    before_spacing = spacing[:before_currency]

    spacing_parts =
      if before_spacing && before_currency_match?(number_string, symbol, before_spacing) do
        [%{type: :literal, value: before_spacing[:insert_between]}]
      else
        []
      end

    [body, spacing_parts, currency_part(symbol)] ++
      [walk_tokens(rest, body, number_string, meta, options)]
  end

  defp walk_tokens(
         [{:currency, _type}, {:format, _} | rest],
         body,
         number_string,
         meta,
         %{currency_spacing: spacing} = options
       )
       when not is_nil(spacing) do
    symbol = options.currency_symbol
    after_spacing = spacing[:after_currency]

    spacing_parts =
      if after_spacing && after_currency_match?(number_string, symbol, after_spacing) do
        [%{type: :literal, value: after_spacing[:insert_between]}]
      else
        []
      end

    [currency_part(symbol), spacing_parts, body] ++
      [walk_tokens(rest, body, number_string, meta, options)]
  end

  defp walk_tokens([{:currency, _type} | rest], body, number_string, meta, options) do
    [
      currency_part(options.currency_symbol)
      | walk_tokens(rest, body, number_string, meta, options)
    ]
  end

  defp walk_tokens([{:format, _} | rest], body, number_string, meta, options) do
    [body | walk_tokens(rest, body, number_string, meta, options)]
  end

  defp walk_tokens([{:pad, _} | rest], body, number_string, meta, options) do
    [
      %{type: :literal, value: padding_string(meta, number_string)}
      | walk_tokens(rest, body, number_string, meta, options)
    ]
  end

  defp walk_tokens([{:plus, _} | rest], body, number_string, meta, options) do
    [
      %{type: :plus_sign, value: options.symbols.plus_sign}
      | walk_tokens(rest, body, number_string, meta, options)
    ]
  end

  defp walk_tokens([{:minus, _} | rest], body, number_string, meta, options) do
    # Mirrors the `{:minus, _}` clause of `assemble_parts/5`: in
    # `:auto` mode a bare zero drops the minus sign.
    auto_sign_display? = options.sign_display in [nil, :auto]

    sign =
      if number_string == "0" and auto_sign_display?, do: "", else: options.symbols.minus_sign

    [
      %{type: :minus_sign, value: sign}
      | walk_tokens(rest, body, number_string, meta, options)
    ]
  end

  defp walk_tokens([{:percent, _} | rest], body, number_string, meta, options) do
    [
      %{type: :percent_sign, value: options.symbols.percent_sign}
      | walk_tokens(rest, body, number_string, meta, options)
    ]
  end

  defp walk_tokens([{:permille, _} | rest], body, number_string, meta, options) do
    [
      %{type: :per_mille, value: options.symbols.per_mille}
      | walk_tokens(rest, body, number_string, meta, options)
    ]
  end

  defp walk_tokens([{:literal, literal} | rest], body, number_string, meta, options) do
    [%{type: :literal, value: literal} | walk_tokens(rest, body, number_string, meta, options)]
  end

  defp walk_tokens([{:quote, _} | rest], body, number_string, meta, options) do
    [%{type: :literal, value: "'"} | walk_tokens(rest, body, number_string, meta, options)]
  end

  defp walk_tokens([{:quoted_char, char} | rest], body, number_string, meta, options) do
    [%{type: :literal, value: char} | walk_tokens(rest, body, number_string, meta, options)]
  end

  defp currency_part(@nbsp), do: []
  defp currency_part(symbol), do: [%{type: :currency, value: symbol}]

  # ── Sign display ────────────────────────────────────────────

  # ECMA-402 `signDisplay` semantics. The `:sign_display` option
  # overrides the sign pattern chosen by `Options.validate_options/2`:
  # `:positive` and `:negative` select the format's subpatterns as
  # usual; the derived `:positive_plus` pattern renders the locale's
  # plus sign (see `pattern_parts/2`). Zero-ness is judged on the
  # digits after rounding, matching ICU — `-0.001` at zero fractional
  # digits is a zero for `:except_zero` and `:negative`.
  defp resolve_sign_display(%{sign_display: sign_display} = options, number, zero?)
       when sign_display in [:always, :except_zero, :negative, :never] do
    %{options | pattern: sign_display_pattern(sign_display, negative_number?(number), zero?)}
  end

  defp resolve_sign_display(options, _number, _zero?) do
    options
  end

  defp sign_display_pattern(:never, _negative?, _zero?), do: :positive
  defp sign_display_pattern(:always, true, _zero?), do: :negative
  defp sign_display_pattern(:always, false, _zero?), do: :positive_plus
  defp sign_display_pattern(:except_zero, _negative?, true), do: :positive
  defp sign_display_pattern(:except_zero, true, false), do: :negative
  defp sign_display_pattern(:except_zero, false, false), do: :positive_plus
  defp sign_display_pattern(:negative, _negative?, true), do: :positive
  defp sign_display_pattern(:negative, true, false), do: :negative
  defp sign_display_pattern(:negative, false, false), do: :positive

  # Per ECMA-402, NaN takes a plus sign under `:always` and no sign
  # under the other explicit modes; `:auto` (and `nil`) keeps the
  # pattern already resolved from the input's sign.
  defp resolve_sign_display_for_nan(%{sign_display: :always} = options) do
    %{options | pattern: :positive_plus}
  end

  defp resolve_sign_display_for_nan(%{sign_display: sign_display} = options)
       when sign_display in [:except_zero, :negative, :never] do
    %{options | pattern: :positive}
  end

  defp resolve_sign_display_for_nan(options) do
    options
  end

  defp negative_number?(%Decimal{sign: sign}), do: sign < 0
  defp negative_number?(number), do: number < 0

  # True when every rounded digit is zero — the displayed value is
  # zero regardless of the exponent.
  defp rounds_to_zero?({_sign, integer, fraction, _exp_sign, _exponent}) do
    Enum.all?(integer, &(&1 == ?0)) and Enum.all?(fraction, &(&1 == ?0))
  end

  # ── Pipeline stages ─────────────────────────────────────────

  defp absolute_value(%Decimal{} = number), do: Decimal.abs(number)
  defp absolute_value(number), do: abs(number)

  defp multiply_by_factor(number, %{multiplier: 1}), do: number

  defp multiply_by_factor(%Decimal{} = number, %{multiplier: factor}) do
    Decimal.mult(number, Decimal.new(factor))
  end

  defp multiply_by_factor(number, %{multiplier: factor}) when is_number(number) do
    # Use Decimal for large floats to avoid ArithmeticError overflow
    if is_float(number) and (abs(number) > 1.0e300 or abs(factor) > 1.0e300) do
      Decimal.mult(Decimal.from_float(number), Decimal.new(factor))
    else
      number * factor
    end
  end

  defp round_to_significant_digits(number, %{significant_digits: %{min: 0, max: 0}}) do
    number
  end

  defp round_to_significant_digits(number, %{significant_digits: %{max: max}}) do
    Math.round_significant(number, max)
  end

  defp round_to_nearest(number, %{round_nearest: rounding}, _options)
       when rounding == 0,
       do: number

  defp round_to_nearest(%Decimal{} = number, %{round_nearest: rounding}, %{
         rounding_mode: rounding_mode
       }) do
    rounding =
      if is_integer(rounding), do: Decimal.new(rounding), else: Decimal.from_float(rounding)

    number
    |> Decimal.div(rounding)
    |> Math.round(0, rounding_mode)
    |> Decimal.mult(rounding)
  end

  defp round_to_nearest(number, %{round_nearest: rounding}, %{rounding_mode: rounding_mode})
       when is_float(number) do
    number
    |> Kernel./(rounding)
    |> Math.round(0, rounding_mode)
    |> Kernel.*(rounding)
  end

  defp round_to_nearest(number, %{round_nearest: rounding}, %{rounding_mode: rounding_mode})
       when is_integer(number) do
    number
    |> Kernel./(rounding)
    |> Math.round(0, rounding_mode)
    |> Kernel.*(rounding)
    |> trunc()
  end

  defp set_exponent(number, %{exponent_digits: 0}), do: {number, 0}

  # TR35 scientific notation. Three flavours, all routed here:
  #
  #   1. Pure scientific (`0.###E0`): mantissa has 1 integer digit, no
  #      shift after `Math.coef_exponent/1`.
  #
  #   2. Engineering (`##0.###E0`, `engineering_grouping = 3`): exponent
  #      forced to a multiple of `engineering_grouping`. The mantissa
  #      shifts right by `exp - floor_div(exp, grouping) * grouping`
  #      positions to absorb the difference.
  #
  #   3. Fixed-width mantissa (`00.###E0`, `min_integer_digits > 1`,
  #      `max == min`, `engineering_grouping = 0`): the mantissa always
  #      shows exactly `min_integer_digits` integer digits, so shift by
  #      `min - 1` regardless of the original exponent.
  #
  # Rounding to the pattern's mantissa precision (`scientific_rounding`)
  # happens BEFORE the shift, on the canonical 1-integer-digit form, so
  # round-up carries cannot perturb the engineering grouping.
  #
  # All numeric inputs are promoted to `%Decimal{}` up front so the
  # shift (a single `exp` field bump on the struct, multiplying by
  # `10^k` exactly) preserves every digit. Float inputs that pass
  # through `Math.coef_exponent/1` directly would surface IEEE 754
  # representation noise once the mantissa is shifted into the visible
  # range — e.g. 12345 → 1.2345 (float) → 12.344999999999999E3 — which
  # the scientific short-circuit in `round_fractional_digits/3` can no
  # longer mask.
  defp set_exponent(number, meta) do
    {coef, exponent} = number |> promote_to_decimal() |> Math.coef_exponent()
    coef = Math.round_significant(coef, meta.scientific_rounding)
    shift = mantissa_shift(exponent, meta)
    {shift_decimal_point_right(coef, shift), exponent - shift}
  end

  defp promote_to_decimal(%Decimal{} = decimal), do: decimal
  defp promote_to_decimal(n) when is_integer(n), do: Decimal.new(n)
  defp promote_to_decimal(n) when is_float(n), do: Decimal.from_float(n)

  # Pure scientific: 1 integer digit, no shift.
  defp mantissa_shift(_exponent, %{engineering_grouping: 0, integer_digits: %{min: min}})
       when min <= 1,
       do: 0

  # Fixed-width mantissa (e.g. `00.###E0`): exactly `min` integer digits.
  defp mantissa_shift(_exponent, %{engineering_grouping: 0, integer_digits: %{min: min}}),
    do: min - 1

  # Engineering (e.g. `##0.###E0`): exponent ≡ 0 (mod grouping).
  defp mantissa_shift(exponent, %{engineering_grouping: group}) when group > 0 do
    exponent - Integer.floor_div(exponent, group) * group
  end

  defp shift_decimal_point_right(%Decimal{} = decimal, 0), do: decimal

  defp shift_decimal_point_right(%Decimal{} = decimal, shift) do
    # `%Decimal{sign, coef, exp}` represents `sign * coef * 10^exp`.
    # Bumping `exp` by `shift` multiplies the value by `10^shift` exactly
    # — no arithmetic, no rounding, no precision loss.
    %{decimal | exp: decimal.exp + shift}
  end

  defp round_fractional_digits({number, exponent}, _meta, _options)
       when is_integer(number) do
    {number, exponent}
  end

  defp round_fractional_digits({number, exponent}, %{exponent_digits: exp_digits}, _options)
       when exp_digits > 0 do
    {number, exponent}
  end

  defp round_fractional_digits({number, exponent}, %{fractional_digits: %{max: max}}, %{
         rounding_mode: rounding_mode
       }) do
    number =
      number
      |> Math.round(max, rounding_mode)
      |> strip_trailing_zeros()

    {number, exponent}
  end

  # `Decimal.round/3` returns a value with exactly the requested scale
  # (e.g., rounding `Decimal.new("1234.56")` to 3 places yields
  # `Decimal<1234.560>`). That surfaces later as a trailing `0` in the
  # fraction tuple and diverges from float behaviour, where the rounding
  # path preserves only the digits actually needed. Normalizing here
  # drops the synthetic trailing zeros; `adjust_trailing_zeros/2` still
  # pads back up to `fractional_digits[:min]` for formats (like
  # currency) that mandate a minimum scale.
  defp strip_trailing_zeros(%Decimal{} = number), do: Decimal.normalize(number)
  defp strip_trailing_zeros(number), do: number

  defp output_to_tuple({coef, exponent}) do
    {integer, fraction, sign} = Digits.to_tuple(coef)
    exponent_sign = if exponent >= 0, do: 1, else: -1
    integer = Enum.map(integer, &Kernel.+(&1, ?0))
    fraction = Enum.map(fraction, &Kernel.+(&1, ?0))
    exponent = if exponent == 0, do: [?0], else: Integer.to_charlist(abs(exponent))
    {sign, integer, fraction, exponent_sign, exponent}
  end

  defp adjust_leading_zeros({sign, integer, fraction, exp_sign, exponent}, %{
         integer_digits: integer_digits
       }) do
    count = integer_digits[:min] - length(integer)

    integer =
      if count > 0 do
        :lists.duplicate(count, ?0) ++ integer
      else
        integer
      end

    {sign, integer, fraction, exp_sign, exponent}
  end

  # ECMA-402 `trailingZeroDisplay: "stripIfInteger"`: when the
  # rounded value is an integer (its fraction has stripped to
  # nothing), suppress the minimum-fraction padding entirely —
  # 1000 with a fraction minimum of 2 renders "1,000" while
  # 1000.5 still renders "1,000.50".
  defp adjust_trailing_zeros({_sign, _integer, [], _exp_sign, _exponent} = digit_tuple, _meta, %{
         trailing_zero_display: :strip_if_integer
       }) do
    digit_tuple
  end

  defp adjust_trailing_zeros(
         {sign, integer, fraction, exp_sign, exponent},
         %{fractional_digits: fraction_digits},
         _options
       ) do
    count = fraction_digits[:min] - length(fraction)

    fraction =
      if count > 0, do: fraction ++ :lists.duplicate(count, ?0), else: fraction

    {sign, integer, fraction, exp_sign, exponent}
  end

  defp set_max_integer_digits(number, %{integer_digits: %{max: 0}}), do: number

  defp set_max_integer_digits({sign, integer, fraction, exp_sign, exponent}, %{
         integer_digits: %{max: max}
       }) do
    over = length(integer) - max

    integer =
      if over > 0 do
        {_rest, kept} = Enum.split(integer, over)
        kept
      else
        integer
      end

    {sign, integer, fraction, exp_sign, exponent}
  end

  defp apply_grouping(
         {sign, integer, [] = fraction, exp_sign, exponent},
         %{grouping: groups},
         options
       ) do
    integer =
      do_grouping(
        integer,
        groups[:integer],
        length(integer),
        minimum_group_size(groups[:integer], options),
        :reverse
      )

    {sign, integer, fraction, exp_sign, exponent}
  end

  defp apply_grouping(
         {sign, integer, fraction, exp_sign, exponent},
         %{grouping: groups},
         options
       ) do
    integer =
      do_grouping(
        integer,
        groups[:integer],
        length(integer),
        minimum_group_size(groups[:integer], options),
        :reverse
      )

    fraction =
      do_grouping(
        fraction,
        groups[:fraction],
        length(fraction),
        minimum_group_size(groups[:fraction], options),
        :forward
      )

    {sign, integer, fraction, exp_sign, exponent}
  end

  defp minimum_group_size(%{first: group_size}, %{
         minimum_grouping_digits: min_digits,
         locale: locale
       }) do
    if is_nil(min_digits) or min_digits == 0 do
      locale_id =
        case locale do
          %Localize.LanguageTag{cldr_locale_id: id} when not is_nil(id) -> id
          %Localize.LanguageTag{} -> :en
          id -> id
        end

      case Localize.Number.Format.minimum_grouping_digits_for(locale_id) do
        {:ok, digits} -> digits + group_size
        _ -> 1 + group_size
      end
    else
      min_digits + group_size
    end
  end

  defp do_grouping(number, _, length, min_grouping, :reverse) when length < min_grouping do
    number
  end

  defp do_grouping(number, %{first: first, rest: first}, length, _, _) when length <= first do
    number
  end

  defp do_grouping(number, %{first: 0, rest: 0}, _, _, _), do: number

  defp do_grouping(number, %{first: 3, rest: 3} = grouping, length, min, :reverse) do
    number
    |> Enum.reverse()
    |> do_grouping(grouping, length, min, :forward)
    |> Enum.reverse()
  end

  defp do_grouping([a, b, c | rest], %{first: 3, rest: 3} = grouping, _length, min, :forward) do
    [a, b, c, @group_separator | do_grouping(rest, grouping, length(rest), min, :forward)]
  end

  defp do_grouping(number, %{first: first, rest: first}, length, _, :forward) do
    split_point = div(length, first) * first
    {rest, last_group} = Enum.split(number, split_point)

    add_separator(rest, first, @group_separator)
    |> add_last_group(last_group, @group_separator)
  end

  defp do_grouping(number, %{first: first, rest: first}, length, _, :reverse) do
    split_point = length - div(length, first) * first
    {first_group, rest} = Enum.split(number, split_point)

    add_separator(rest, first, @group_separator)
    |> add_first_group(first_group, @group_separator)
  end

  defp do_grouping(number, %{first: first, rest: rest}, length, _min, :reverse) do
    {others, first_group} = Enum.split(number, length - first)

    do_grouping(others, %{first: rest, rest: rest}, length(others), 1, :reverse)
    |> add_last_group(first_group, @group_separator)
  end

  defp add_separator([], _every, _separator), do: []

  defp add_separator(group, every, separator) do
    {_, [_ | rest]} =
      Enum.reduce(group, {1, []}, fn elem, {counter, list} ->
        list = [elem | list]
        list = if rem(counter, every) == 0, do: [separator | list], else: list
        {counter + 1, list}
      end)

    Enum.reverse(rest)
  end

  defp add_first_group(groups, [], _separator), do: groups
  defp add_first_group(groups, first, separator), do: [first, separator, groups]

  defp add_last_group(groups, [], _separator), do: groups
  defp add_last_group(groups, last, separator), do: [groups, separator, last]

  defp reassemble_number_string(
         {_sign, integer, fraction, exponent_sign, exponent},
         meta,
         options
       ) do
    decimal_sep = decimal_separator(options, @decimal_separator)
    integer = if integer == [], do: [~c"0"], else: integer
    fraction = if fraction == [], do: fraction, else: [decimal_sep, fraction]

    exponent_part =
      if meta.exponent_digits > 0 do
        digits =
          exponent
          |> List.to_string()
          |> String.pad_leading(meta.exponent_digits, "0")

        case Map.get(options, :exponent_style) do
          :superscript -> superscript_exponent_part(exponent_sign, digits, meta, options)
          _ -> default_exponent_part(exponent_sign, digits, meta, options)
        end
      else
        []
      end

    [integer, fraction, exponent_part]
    |> :erlang.iolist_to_binary()
  end

  defp default_exponent_part(exponent_sign, digits, meta, options) do
    exp_sign =
      cond do
        exponent_sign < 0 -> exponent_minus_symbol(options)
        meta.exponent_sign -> exponent_plus_symbol(options)
        true -> ~c""
      end

    [exponent_separator_symbol(options), exp_sign, digits]
  end

  # `:exponent_style => :superscript` renders the `1.23 × 10⁴` form
  # advertised by TR35 via the `superscriptingExponent` symbol (CLDR
  # universally ships `"×"` / U+00D7). The `10` is rendered in Latin
  # digits up front and transliterated later by `transliterate_string/2`
  # to the active number system. The exponent itself uses Unicode
  # superscript characters — these are not in any number-system digit
  # set, so they pass through the digit transliteration map unchanged.
  defp superscript_exponent_part(exponent_sign, digits, meta, options) do
    sign_glyph =
      cond do
        exponent_sign < 0 -> "⁻"
        meta.exponent_sign -> "⁺"
        true -> ""
      end

    super_digits =
      digits
      |> String.graphemes()
      |> Enum.map_join(&superscript_digit/1)

    [superscripting_symbol(options), "10", sign_glyph, super_digits]
  end

  defp superscripting_symbol(%{symbols: %{superscripting_exponent: s}})
       when is_binary(s) and s != "",
       do: s

  defp superscripting_symbol(_options), do: "×"

  @superscript_digits %{
    "0" => "⁰",
    "1" => "¹",
    "2" => "²",
    "3" => "³",
    "4" => "⁴",
    "5" => "⁵",
    "6" => "⁶",
    "7" => "⁷",
    "8" => "⁸",
    "9" => "⁹"
  }

  defp superscript_digit(grapheme), do: Map.get(@superscript_digits, grapheme, grapheme)

  # Locale-aware exponent symbols. CLDR's `symbols-numberSystem-…`
  # block carries `exponential` (e.g. "E" in `en`, "أس" in `ar/arab`,
  # "×۱۰^" in `fa/arabext`), `minusSign`, and `plusSign`. When no
  # symbol set is configured — raw `Format.to_string/2` callers, the
  # compiler-only tests, etc. — we fall back to the compile-time ASCII
  # placeholders.
  defp exponent_separator_symbol(%{symbols: %{exponential: e}})
       when is_binary(e) and e != "",
       do: e

  defp exponent_separator_symbol(_options), do: @exponent_separator

  defp exponent_minus_symbol(%{symbols: %{minus_sign: m}})
       when is_binary(m) and m != "",
       do: m

  defp exponent_minus_symbol(_options), do: @minus_placeholder

  defp exponent_plus_symbol(%{symbols: %{plus_sign: p}})
       when is_binary(p) and p != "",
       do: p

  defp exponent_plus_symbol(_options), do: @exponent_sign

  defp transliterate_string(number_string, %{number_system: :latn} = options) do
    transliterate_separators(number_string, options)
  end

  defp transliterate_string(number_string, %{number_system: nil} = options) do
    transliterate_separators(number_string, options)
  end

  defp transliterate_string(number_string, %{number_system: number_system} = options) do
    translated =
      with {:ok, digits} <- Localize.Number.System.number_system_digits(number_system),
           {:ok, latn_digits} <- Localize.Number.System.number_system_digits(:latn) do
        map = Localize.Number.System.generate_transliteration_map(latn_digits, digits)
        Localize.Number.Transliterate.transliterate_digits(number_string, map)
      else
        # `:latn` digits are bundled in the supplemental data and should
        # always resolve, but if either side fails we leave the digits
        # untransliterated rather than crashing the whole format pipeline.
        _ -> number_string
      end

    transliterate_separators(translated, options)
  end

  # Replace placeholder separators (,.) with locale-specific symbols
  defp transliterate_separators(number_string, %{symbols: nil}), do: number_string

  defp transliterate_separators(number_string, %{symbols: symbols}) do
    group_sym = extract_symbol(symbols.group)
    decimal_sym = extract_symbol(symbols.decimal)

    # If both are the same as placeholders, nothing to do
    if (group_sym == @group_separator or group_sym == nil) and
         (decimal_sym == @decimal_separator or decimal_sym == nil) do
      number_string
    else
      # Single-pass replacement to avoid conflicts when separators
      # swap (e.g., German: "," → "." and "." → ",")
      number_string
      |> String.graphemes()
      |> Enum.map_join(fn
        @group_separator -> group_sym || @group_separator
        @decimal_separator -> decimal_sym || @decimal_separator
        char -> char
      end)
    end
  end

  defp extract_symbol(%{standard: value}), do: value
  defp extract_symbol(value) when is_binary(value), do: value
  defp extract_symbol(_), do: ""

  defp assemble_format(number_string, meta, options) do
    format = pattern_parts(meta.format, options.pattern)
    number = meta.number

    assemble_parts(format, number_string, number, meta, options)
    |> :erlang.iolist_to_binary()
    |> String.trim_trailing()
  end

  # The `:positive_plus` pattern is derived, not compiled: it is the
  # negative subpattern with the minus token replaced by the locale's
  # plus sign. When the negative subpattern carries no minus token
  # (an explicit subpattern such as accounting's `(¤#,##0.00)`), the
  # plus sign is prefixed to the positive subpattern instead — the
  # ICU behaviour behind ECMA-402's `+$1.00` / `($1.00)` pairing for
  # accounting formats with `signDisplay: "always"`.
  defp pattern_parts(format, :positive_plus) do
    negative = format[:negative] || []

    if Enum.any?(negative, &match?({:minus, _}, &1)) do
      Enum.map(negative, fn
        {:minus, _} -> {:plus, nil}
        part -> part
      end)
    else
      [{:plus, nil} | format[:positive]]
    end
  end

  defp pattern_parts(format, pattern) do
    format[pattern]
  end

  # ── Format assembly ─────────────────────────────────────────

  defp assemble_parts([], _number_string, _number, _meta, _options), do: []

  defp assemble_parts(
         [{:format, _}, {:currency, _type} | rest],
         number_string,
         number,
         meta,
         %{currency_spacing: spacing} = options
       )
       when not is_nil(spacing) do
    %{currency_symbol: symbol, wrapper: wrapper} = options

    symbol = maybe_wrap(symbol, :currency_symbol, wrapper)
    number_string_wrapped = maybe_wrap(number_string, :number, wrapper)

    before_spacing = spacing[:before_currency]

    if before_spacing && before_currency_match?(number_string, symbol, before_spacing) do
      [
        number_string_wrapped,
        maybe_wrap(before_spacing[:insert_between], :currency_space, wrapper),
        symbol
        | assemble_parts(rest, number_string, number, meta, options)
      ]
    else
      [
        number_string_wrapped,
        symbol
        | assemble_parts(rest, number_string, number, meta, options)
      ]
    end
  end

  defp assemble_parts(
         [{:currency, _type}, {:format, _} | rest],
         number_string,
         number,
         meta,
         %{currency_spacing: spacing} = options
       )
       when not is_nil(spacing) do
    %{currency_symbol: symbol, wrapper: wrapper} = options

    symbol = maybe_wrap(symbol, :currency_symbol, wrapper)
    number_string_wrapped = maybe_wrap(number_string, :number, wrapper)

    after_spacing = spacing[:after_currency]

    if after_spacing && after_currency_match?(number_string, symbol, after_spacing) do
      [
        symbol,
        maybe_wrap(after_spacing[:insert_between], :currency_space, wrapper),
        number_string_wrapped
        | assemble_parts(rest, number_string, number, meta, options)
      ]
    else
      [
        symbol,
        number_string_wrapped
        | assemble_parts(rest, number_string, number, meta, options)
      ]
    end
  end

  defp assemble_parts([{:currency, _type} | rest], number_string, number, meta, options) do
    %{currency_symbol: symbol, wrapper: wrapper} = options

    if symbol == @nbsp do
      assemble_parts(rest, number_string, number, meta, options)
    else
      symbol = maybe_wrap(symbol, :currency_symbol, wrapper)
      [symbol | assemble_parts(rest, number_string, number, meta, options)]
    end
  end

  defp assemble_parts(
         [{:format, _} | rest],
         number_string,
         number,
         meta,
         %{wrapper: wrapper} = options
       ) do
    [
      maybe_wrap(number_string, :number, wrapper)
      | assemble_parts(rest, number_string, number, meta, options)
    ]
  end

  defp assemble_parts([{:pad, _} | rest], number_string, number, meta, options) do
    [
      padding_string(meta, number_string)
      | assemble_parts(rest, number_string, number, meta, options)
    ]
  end

  defp assemble_parts(
         [{:plus, _} | rest],
         number_string,
         number,
         meta,
         %{wrapper: wrapper} = options
       ) do
    [
      maybe_wrap(options.symbols.plus_sign, :plus, wrapper)
      | assemble_parts(rest, number_string, number, meta, options)
    ]
  end

  defp assemble_parts(
         [{:minus, _} | rest],
         number_string,
         number,
         meta,
         %{wrapper: wrapper} = options
       ) do
    # In `:auto` mode a bare zero drops the minus sign. With an
    # explicit `:sign_display`, `resolve_sign_display/3` has already
    # decided whether this zero shows its sign (`:always` keeps the
    # minus on `-0`), so the pattern choice is final.
    auto_sign_display? = options.sign_display in [nil, :auto]

    sign =
      if(number_string == "0" and auto_sign_display?, do: "", else: options.symbols.minus_sign)
      |> maybe_wrap(:minus, wrapper)

    [sign | assemble_parts(rest, number_string, number, meta, options)]
  end

  defp assemble_parts(
         [{:percent, _} | rest],
         number_string,
         number,
         meta,
         %{wrapper: wrapper} = options
       ) do
    [
      maybe_wrap(options.symbols.percent_sign, :percent, wrapper)
      | assemble_parts(rest, number_string, number, meta, options)
    ]
  end

  defp assemble_parts(
         [{:permille, _} | rest],
         number_string,
         number,
         meta,
         %{wrapper: wrapper} = options
       ) do
    [
      maybe_wrap(options.symbols.per_mille, :permille, wrapper)
      | assemble_parts(rest, number_string, number, meta, options)
    ]
  end

  defp assemble_parts(
         [{:literal, literal} | rest],
         number_string,
         number,
         meta,
         %{wrapper: wrapper} = options
       ) do
    [
      maybe_wrap(literal, :literal, wrapper)
      | assemble_parts(rest, number_string, number, meta, options)
    ]
  end

  defp assemble_parts(
         [{:quote, _} | rest],
         number_string,
         number,
         meta,
         %{wrapper: wrapper} = options
       ) do
    [
      maybe_wrap("'", :quote, wrapper)
      | assemble_parts(rest, number_string, number, meta, options)
    ]
  end

  defp assemble_parts([{:quoted_char, char} | rest], number_string, number, meta, options) do
    [char | assemble_parts(rest, number_string, number, meta, options)]
  end

  defp maybe_wrap(string, _tag, nil), do: string

  defp maybe_wrap(string, tag, wrapper) do
    case wrapper.(string, tag) do
      {:safe, iodata} -> iodata
      iodata when is_list(iodata) -> iodata
      string when is_binary(string) -> string
    end
  end

  defp padding_string(%{padding_length: 0}, _number_string), do: @empty_string

  defp padding_string(meta, number_string) do
    pad_length = meta.padding_length - String.length(number_string)

    if pad_length > 0 do
      String.duplicate(meta.padding_char, pad_length)
    else
      @empty_string
    end
  end

  # ── Meta adjustments ───────────────────────────────────────

  defp adjust_fraction_for_currency(meta, nil, _currency_digits), do: meta

  defp adjust_fraction_for_currency(meta, %Localize.Currency{} = currency, :accounting) do
    do_adjust_fraction(meta, currency.digits, currency.rounding)
  end

  defp adjust_fraction_for_currency(meta, %Localize.Currency{} = currency, :cash) do
    do_adjust_fraction(meta, currency.cash_digits, currency.cash_rounding)
  end

  defp adjust_fraction_for_currency(meta, %Localize.Currency{} = currency, :iso) do
    do_adjust_fraction(meta, currency.iso_digits, currency.iso_digits)
  end

  defp adjust_fraction_for_currency(meta, _currency, _digits), do: meta

  defp do_adjust_fraction(meta, digits, rounding) do
    rounding = Math.power(10, -digits) * rounding
    %{meta | round_nearest: rounding}
  end

  defp adjust_fraction_for_significant_digits(%{significant_digits: nil} = meta, _number) do
    meta
  end

  defp adjust_fraction_for_significant_digits(
         %{significant_digits: %{max: 0, min: 0}} = meta,
         _number
       ) do
    meta
  end

  # When significant digits are active they own the fraction display,
  # per TR35/ICU. Enough fraction digits are forced to reach `min`
  # significant digits (1.0 at min 3 → "1.00") and none are forced when
  # the rounded value already carries them in its integer part
  # (1234.567 at max 3 → "1,230", not "1,230.0"). The max of 10 stops
  # the pattern's fractional limit from clipping small values like
  # 0.00123 whose significant digits sit deep in the fraction.
  # `number_of_integer_digits/1` returns 0 for |value| < 1, so sub-one
  # values force `min` fraction digits — the integer zero in "0.5" is
  # not a significant digit.
  defp adjust_fraction_for_significant_digits(
         %{significant_digits: %{min: min_sig, max: max_sig}} = meta,
         number
       ) do
    rounded = Math.round_significant(number, max_sig)
    integer_digit_count = Digits.number_of_integer_digits(rounded)
    fraction_min = max(min_sig - integer_digit_count, 0)

    %{meta | fractional_digits: %{max: 10, min: fraction_min}}
  end

  defp adjust_for_fractional_digits(meta, options) do
    fd = options.fractional_digits
    min_fd = options.min_fractional_digits
    max_fd = options.max_fractional_digits

    cond do
      # Explicit min/max take precedence
      min_fd != nil or max_fd != nil ->
        min_val = min_fd || fd || meta.fractional_digits[:min]
        max_val = max_fd || fd || meta.fractional_digits[:max]
        %{meta | fractional_digits: %{max: max_val, min: min_val}}

      # Legacy :fractional_digits sets both min and max
      fd != nil ->
        %{meta | fractional_digits: %{max: fd, min: fd}}

      # No override — keep format-derived defaults
      true ->
        meta
    end
  end

  defp adjust_for_integer_digits(meta, nil), do: meta

  defp adjust_for_integer_digits(meta, digits) do
    integer_digits = Map.put(meta.integer_digits, :max, digits)
    %{meta | integer_digits: integer_digits}
  end

  # ECMA-402 `minimumIntegerDigits`: zero-pad the integer part to
  # the requested width. The pipeline pads via
  # `adjust_leading_zeros/2` before grouping is applied, so the
  # padding digits group like ordinary digits ("00,123").
  defp adjust_for_minimum_integer_digits(meta, nil), do: meta

  defp adjust_for_minimum_integer_digits(meta, digits) do
    integer_digits = Map.put(meta.integer_digits, :min, digits)
    %{meta | integer_digits: integer_digits}
  end

  defp adjust_for_round_nearest(meta, nil), do: meta
  defp adjust_for_round_nearest(meta, digits), do: %{meta | round_nearest: digits}

  # ── Currency spacing helpers ────────────────────────────────

  @currency_match_symbol "[\\P{S}]$"
  @currency_match_separator "[\\P{Z}]$"

  defp before_currency_match?(
         number_string,
         symbol,
         %{currency_match: "[[:^S:]&[:^Z:]]"} = spacing
       ) do
    String.match?(number_string, Regex.compile!(spacing[:surrounding_match] <> "$", "u")) &&
      String.match?(to_string(symbol), ~r/#{@currency_match_symbol}/u) &&
      String.match?(to_string(symbol), ~r/#{@currency_match_separator}/u)
  end

  defp before_currency_match?(number_string, symbol, spacing) do
    String.match?(number_string, Regex.compile!(spacing[:surrounding_match] <> "$", "u")) &&
      String.match?(to_string(symbol), Regex.compile!("^" <> spacing[:currency_match], "u"))
  end

  defp after_currency_match?(
         number_string,
         symbol,
         %{currency_match: "[[:^S:]&[:^Z:]]"} = spacing
       ) do
    String.match?(number_string, Regex.compile!("^" <> spacing[:surrounding_match], "u")) &&
      String.match?(to_string(symbol), ~r/#{@currency_match_symbol}/u) &&
      String.match?(to_string(symbol), ~r/#{@currency_match_separator}/u)
  end

  defp after_currency_match?(number_string, symbol, spacing) do
    String.match?(number_string, Regex.compile!("^" <> spacing[:surrounding_match], "u")) &&
      String.match?(to_string(symbol), Regex.compile!(spacing[:currency_match] <> "$", "u"))
  end

  defp decimal_separator(%{currency: %{decimal_separator: nil}}, default), do: default
  defp decimal_separator(%{currency: %{decimal_separator: sep}}, _default), do: sep
  defp decimal_separator(_options, default), do: default
end
