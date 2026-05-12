defmodule Localize.Number.Formatter.Decimal do
  @moduledoc false

  # Formats a number according to a locale-specific format pattern.
  #
  # This is the core number formatting engine. It takes a number,
  # parses it according to the format metadata, applies grouping,
  # rounding, transliteration, and assembles the final string.

  alias Localize.Number.Format.Compiler
  alias Localize.Number.Format.Options
  alias Localize.Utils.{Math, Digits}

  @empty_string ""

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
    meta
    |> apply_significant_digit_options(options)
    |> adjust_fraction_for_currency(options.currency, options.currency_digits)
    |> adjust_fraction_for_significant_digits(number)
    |> adjust_for_fractional_digits(options)
    |> adjust_for_integer_digits(options.maximum_integer_digits)
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

    cond do
      is_nil(min) and is_nil(max) ->
        meta

      true ->
        resolved_min = min || 1
        resolved_max = max || 21
        %{meta | significant_digits: %{min: resolved_min, max: resolved_max}}
    end
  end

  # ── Core formatting pipeline ──────────────────────────────

  defp do_to_string(%Decimal{coef: :NaN}, meta, options) do
    options.symbols.nan
    |> assemble_format(meta, options)
  end

  defp do_to_string(%Decimal{coef: :inf}, meta, options) do
    options.symbols.infinity
    |> assemble_format(meta, options)
  end

  defp do_to_string(string, meta, options) when is_binary(string) do
    assemble_format(string, meta, options)
  end

  defp do_to_string(number, %{integer_digits: _} = meta, options) do
    number
    |> absolute_value()
    |> multiply_by_factor(meta)
    |> round_to_significant_digits(meta)
    |> round_to_nearest(meta, options)
    |> set_exponent(meta)
    |> round_fractional_digits(meta, options)
    |> output_to_tuple()
    |> adjust_leading_zeros(meta)
    |> adjust_trailing_zeros(meta)
    |> set_max_integer_digits(meta)
    |> apply_grouping(meta, options)
    |> reassemble_number_string(meta, options)
    |> transliterate_string(options)
    |> assemble_format(meta, options)
  end

  defp do_to_string(number, meta, options) do
    assemble_format(number, meta, options)
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

  defp set_exponent(number, meta) do
    {coef, exponent} = Math.coef_exponent(number)
    coef = Math.round_significant(coef, meta.scientific_rounding)
    {coef, exponent}
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
    integer =
      if (count = integer_digits[:min] - length(integer)) > 0 do
        :lists.duplicate(count, ?0) ++ integer
      else
        integer
      end

    {sign, integer, fraction, exp_sign, exponent}
  end

  defp adjust_trailing_zeros({sign, integer, fraction, exp_sign, exponent}, %{
         fractional_digits: fraction_digits
       }) do
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

  @group_separator Compiler.placeholder(:group)

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

  @decimal_separator Compiler.placeholder(:decimal)
  @exponent_separator Compiler.placeholder(:exponent)
  @exponent_sign Compiler.placeholder(:exponent_sign)
  @minus_placeholder Compiler.placeholder(:minus)

  defp reassemble_number_string(
         {_sign, integer, fraction, exponent_sign, exponent},
         meta,
         options
       ) do
    decimal_sep = decimal_separator(options, @decimal_separator)
    integer = if integer == [], do: [~c"0"], else: integer
    fraction = if fraction == [], do: fraction, else: [decimal_sep, fraction]

    exp_sign =
      cond do
        exponent_sign < 0 -> @minus_placeholder
        meta.exponent_sign -> @exponent_sign
        true -> ~c""
      end

    exponent_part =
      if meta.exponent_digits > 0 do
        digits =
          exponent
          |> List.to_string()
          |> String.pad_leading(meta.exponent_digits, "0")

        [@exponent_separator, exp_sign, digits]
      else
        []
      end

    [integer, fraction, exponent_part]
    |> :erlang.iolist_to_binary()
  end

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
      |> Enum.map(fn
        @group_separator -> group_sym || @group_separator
        @decimal_separator -> decimal_sym || @decimal_separator
        char -> char
      end)
      |> Enum.join()
    end
  end

  defp extract_symbol(%{standard: value}), do: value
  defp extract_symbol(value) when is_binary(value), do: value
  defp extract_symbol(_), do: ""

  defp assemble_format(number_string, meta, options) do
    format = meta.format[options.pattern]
    number = meta.number

    assemble_parts(format, number_string, number, meta, options)
    |> :erlang.iolist_to_binary()
    |> String.trim_trailing()
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

  @nbsp "\u200b"

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
    sign =
      if(number_string == "0", do: "", else: options.symbols.minus_sign)
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

  defp adjust_fraction_for_significant_digits(%{significant_digits: _} = meta, number)
       when is_integer(number) do
    meta
  end

  defp adjust_fraction_for_significant_digits(%{significant_digits: _} = meta, %Decimal{exp: exp})
       when exp >= 0 do
    meta
  end

  defp adjust_fraction_for_significant_digits(%{significant_digits: _} = meta, _number) do
    %{meta | fractional_digits: %{max: 10, min: 1}}
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
