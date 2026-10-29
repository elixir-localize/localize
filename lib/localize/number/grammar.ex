defmodule Localize.Number.Grammar do
  @moduledoc """
  The grammar of a number, read from the tokens of
  `Localize.Number.Lexer` with a `t:Localize.Number.Lexicon.t/0`.

  A number is read once with each of the lexicon's readings, the
  separator sets it may be written with, and is the value every valid
  reading gives. Where two readings give different values the text is
  refused as ambiguous rather than one guessed.

  ## Grammar

  ```ebnf
  number    = lead, body, trail ;
  lead      = spaces, [ sign ], spaces, [ "(" ], spaces, [ sign ], spaces ;
  trail     = spaces, [ sign ], spaces, [ ")" ], spaces, [ sign ], spaces ;
  body      = integer, [ decimal, fraction ], [ exponent ] ;
  integer   = digits, { group, digits } ;
  fraction  = digits | zero-dash ;
  zero-dash = dash, [ dash ] ;
  exponent  = ( "e" | "E" ), [ sign ], digits ;
  ```

  `decimal` and `group` are the marks of the reading in hand, and a
  space is a `group` where the reading groups with one. The rules a
  number must also satisfy are the named functions below, each with
  the TR35 passage or decision it comes from:

  * one sign at most, before or after the digits, or parentheses,
    which make the number negative (`signed_body/2`);

  * no minus before a bare decimal mark, since "-.5" may be a zero
    written as a dash (`dash_for_zero?/4`);

  * a zero fraction written as one or two dashes, leniently only
    (`zero_fraction/3`);

  * no space inside the number unless the reading groups with one
    (`no_interior_space/2`);

  * no group separator in the fraction (`no_grouped_fraction/2`);

  * groups of the sizes the grouping mode allows
    (`integer_grouping/3`);

  * no period that is foreign to every reading, unless it is one
    decimal point between digits and not a thousands group
    (`no_stray_period/3`);

  * Elixir's digit separator `_` only between two digits
    (`join_underscores/1`).

  """

  alias Localize.Number.{Lexer, Lexicon}

  @type number_type :: :integer | :float | :decimal | nil
  @type grouping :: :lenient | :strict | :sizes

  # The shortest group a lenient reading accepts between the first and the
  # last.
  @lenient_group_floor 2

  @doc """
  Reads a number from a string with a lexicon.

  ### Arguments

  * `string` is the text to read.

  * `lexicon` is the `t:Localize.Number.Lexicon.t/0` to read it with.

  * `options` is a keyword list of options.

  ### Options

  * `:number` is the type to read: `:integer`, `:float`, `:decimal`,
    or `nil` to read an integer where the text is one and a float
    otherwise.

  * `:grouping` is how group separators are checked: `:lenient`,
    `:strict` or `:sizes`.

  * `:max_decimal_exponent` bounds the exponent of a decimal read.

  ### Returns

  * `{:ok, number}`, or

  * `{:error, %Localize.InvalidValueError{}}` when the text is not a
    number of the lexicon's locale, or

  * `{:error, %Localize.ParseError{reason: :unexpected_input}}` when
    two readings give different numbers.

  ### Examples

      iex> {:ok, de} = Localize.validate_locale(:de)
      iex> {:ok, lexicon} = Localize.Number.Lexicon.fetch(de, :latn, [])
      iex> Localize.Number.Grammar.read("1.234,5", lexicon, number: :decimal, grouping: :lenient)
      {:ok, Decimal.new("1234.5")}

  """
  @spec read(String.t(), Lexicon.t(), Keyword.t()) ::
          {:ok, number() | Decimal.t()} | {:error, Exception.t()}
  def read(string, %Lexicon{} = lexicon, options) do
    number_type = Keyword.get(options, :number)
    grouping = Keyword.get(options, :grouping, :lenient)
    max_exponent = Keyword.get(options, :max_decimal_exponent)

    tokens =
      string
      |> Lexer.tokens(lexicon)
      |> drop_format_characters()
      |> join_underscores()

    lexicon.readings
    |> Enum.map(&read_with(tokens, &1, lexicon, string, number_type, grouping, max_exponent))
    |> agreed_reading(string)
  end

  # ── Readings ──────────────────────────────────────────────────

  # Text that is not a number of this reading is an error naming the text,
  # not whichever rule refused it.
  defp read_with(tokens, reading, lexicon, string, number_type, grouping, max_exponent) do
    case number_value(tokens, reading, lexicon, number_type, grouping) do
      {:ok, value} -> bound_decimal_exponent(value, max_exponent)
      {:error, _rule} -> {:error, parse_error(string)}
    end
  end

  defp number_value(tokens, reading, lexicon, number_type, grouping) do
    with {:ok, number} <- number_string(tokens, reading, lexicon, grouping) do
      parse_number(number, number_type)
    end
  end

  # A number is the one every valid reading gives. Where two readings are
  # valid and differ, the text is ambiguous: with `root_separators: true`,
  # `de` "1.234" is 1234 with the locale's separators and 1.234 with the
  # root locale's.
  defp agreed_reading(readings, string) do
    values = for {:ok, value} <- readings, do: value

    case values do
      [] -> hd(readings)
      [value | others] -> same_reading(value, others, string)
    end
  end

  defp same_reading(value, others, string) do
    case Enum.reject(others, &same_value?(&1, value)) do
      [] -> {:ok, value}
      [other | _] -> {:error, ambiguous_number(string, value, other)}
    end
  end

  defp same_value?(%Decimal{} = this, %Decimal{} = that) do
    Decimal.equal?(this, that)
  end

  defp same_value?(this, that) do
    this == that
  end

  # ── The number of one reading ─────────────────────────────────

  defp number_string(tokens, reading, lexicon, grouping) do
    reversed = tokens |> Enum.reverse() |> zero_fraction(reading, grouping)

    with {:ok, body, negative?} <- signed_body(reversed, reading),
         :ok <- no_interior_space(body, reading),
         {integer, decimal, fraction} = split_decimal(body, reading),
         :ok <- no_grouped_fraction(fraction, reading),
         :ok <- integer_grouping(integer, reading, grouping),
         :ok <- no_stray_period(body, reading, lexicon) do
      number =
        (integer ++ decimal ++ fraction)
        |> Enum.map_join(&token_text(&1, reading))
        |> complete_decimal_point()

      {:ok, signed(number, negative?)}
    end
  end

  # Format characters are dropped anywhere in a number, as TR35's loose
  # matching says: CLDR puts bidi marks in the signs of nineteen locales.
  defp drop_format_characters(tokens) do
    Enum.reject(tokens, fn {kind, _value, _source} -> kind in [:bidi, :format] end)
  end

  # Elixir writes `1_000_000`, with the underscore between two digits.
  # Anywhere else it is not part of a number (decided 2026-10-29; the
  # parser before this one dropped it anywhere).
  defp join_underscores([
         {:digits, a, a_source},
         {:underscore, _, _},
         {:digits, b, b_source} | rest
       ]) do
    join_underscores([{:digits, a <> b, a_source <> "_" <> b_source} | rest])
  end

  defp join_underscores([token | rest]) do
    [token | join_underscores(rest)]
  end

  defp join_underscores([]) do
    []
  end

  # Swiss "5.–" and Dutch "5,-" write a whole amount with a dash for its
  # fraction, one dash or two of the same kind. CLDR has no data for the
  # convention (CLDR-3394), so it is read only leniently. The dashes end
  # the number, which may be followed by the closing parenthesis of an
  # accounting format: "(CHF 5.–)". Read from the end, on the reversed
  # tokens, which `trail/1` then takes up.
  defp zero_fraction(reversed, reading, grouping) when grouping in [:lenient, :sizes] do
    {closing, before} = split_closing(reversed)

    case drop_zero_dashes(before, reading) do
      {:ok, whole} -> closing ++ whole
      :none -> reversed
    end
  end

  defp zero_fraction(reversed, _reading, :strict) do
    reversed
  end

  # The spaces, closing parenthesis and spaces that may end a number, taken
  # from the reversed tokens.
  defp split_closing(reversed) do
    {spaces_after, reversed} = Enum.split_while(reversed, &space?/1)
    {close, reversed} = take_kind(reversed, :close)
    {spaces_before, reversed} = Enum.split_while(reversed, &space?/1)
    {spaces_after ++ close ++ spaces_before, reversed}
  end

  defp drop_zero_dashes([first, second, mark, digit | whole], reading) do
    if dash_pair?(first, second) and decimal?(mark, reading) and digit?(digit) do
      {:ok, [digit | whole]}
    else
      drop_zero_dash([first, second, mark, digit | whole], reading)
    end
  end

  defp drop_zero_dashes(reversed, reading) do
    drop_zero_dash(reversed, reading)
  end

  defp drop_zero_dash([dash, mark, digit | whole], reading) do
    if dash?(dash) and decimal?(mark, reading) and digit?(digit) do
      {:ok, [digit | whole]}
    else
      :none
    end
  end

  defp drop_zero_dash(_reversed, _reading) do
    :none
  end

  # Two dashes stand for a zero fraction only when they are alike: both a
  # minus, or both the same dash.
  defp dash_pair?({:minus, _, _}, {:minus, _, _}) do
    true
  end

  defp dash_pair?({:dash, _, dash}, {:dash, _, dash}) do
    true
  end

  defp dash_pair?(_first, _second) do
    false
  end

  # A number's sign or accounting parentheses, as a money amount writes
  # them: one sign at most, before or after the digits, or parentheses,
  # which make it negative, so "(5)" is -5. TR35's heuristics for parsing
  # a number take a sign as a prefix or a suffix. A sign and parentheses
  # together are refused: "(-5)" is read as -5 by some and as 5 by others.
  defp signed_body(reversed, reading) do
    {after_close, close, before_close, tokens} = trail(reversed)
    {before_open, open, after_open, body} = lead(tokens)
    signs = Enum.reject([before_open, after_open, before_close, after_close], &is_nil/1)

    cond do
      body == [] -> {:error, :no_digits}
      match?([_, _ | _], signs) -> {:error, :signs}
      open != close -> {:error, :parentheses}
      open and signs != [] -> {:error, :signs}
      dash_for_zero?(before_open, after_open, body, reading) -> {:error, :dash_for_zero}
      true -> {:ok, body, signs == [:minus] or open}
    end
  end

  # The spaces, sign, opening parenthesis and sign a number may start
  # with, in that order, each optional.
  defp lead(tokens) do
    {first_sign, tokens} = tokens |> drop_spaces() |> take_sign()
    {open, tokens} = tokens |> drop_spaces() |> take_kind(:open)
    {second_sign, tokens} = tokens |> drop_spaces() |> take_sign()
    {first_sign, open != [], second_sign, drop_spaces(tokens)}
  end

  # The same at the end, read from the reversed tokens, which it hands back
  # in order.
  defp trail(reversed) do
    {last_sign, reversed} = reversed |> drop_spaces() |> take_sign()
    {close, reversed} = reversed |> drop_spaces() |> take_kind(:close)
    {inner_sign, reversed} = reversed |> drop_spaces() |> take_sign()
    {last_sign, close != [], inner_sign, reversed |> drop_spaces() |> Enum.reverse()}
  end

  # A minus before a decimal mark with no digit ahead of it is refused:
  # Swiss "Fr. –.15" and Dutch "€ -,50" write a dash for the zero there,
  # so "-.15" may be 0.15 or -0.15.
  defp dash_for_zero?(before_open, after_open, [first | _rest], reading) do
    :minus in [before_open, after_open] and decimal?(first, reading)
  end

  # A number is digits joined by the locale's separators. Where the
  # reading groups with a space, every space is a separator; anywhere
  # else a space inside the number parts two numbers, as `scan/2` reads
  # them, so `en` "1 2" is not 12 (user, 2026-10-28). A space beside a
  # sign is not inside the number.
  defp no_interior_space(_body, %{space_group?: true}) do
    :ok
  end

  defp no_interior_space(body, _reading) do
    if interior_space?(body) do
      {:error, :interior_space}
    else
      :ok
    end
  end

  defp interior_space?([sign, space | rest])
       when elem(sign, 0) in [:minus, :plus] and elem(space, 0) == :space do
    interior_space?(rest)
  end

  defp interior_space?([space, sign | rest])
       when elem(space, 0) == :space and elem(sign, 0) in [:minus, :plus] do
    interior_space?([sign | rest])
  end

  defp interior_space?([{:space, _, _} | _rest]) do
    true
  end

  defp interior_space?([_token | rest]) do
    interior_space?(rest)
  end

  defp interior_space?([]) do
    false
  end

  # The integer part, the first decimal mark and what follows it.
  defp split_decimal(body, reading) do
    case Enum.split_while(body, &(not decimal?(&1, reading))) do
      {integer, [decimal | fraction]} -> {integer, [decimal], fraction}
      {integer, []} -> {integer, [], []}
    end
  end

  # Digits after the decimal mark are never grouped, so a group separator
  # there means the text is not a number of this reading: `de` "1,234.56"
  # is not 1.23456, nor `fr` "1,5 6" 1.56.
  defp no_grouped_fraction(fraction, reading) do
    if Enum.any?(fraction, &group?(&1, reading)) do
      {:error, :grouping}
    else
      :ok
    end
  end

  # Grouping is optional in input, so an integer with no separator is
  # taken as it is. With separators, every group is digits, and of a size
  # the mode allows. An exponent's sign is not part of the integer.
  defp integer_grouping(integer, reading, grouping) do
    integer = Enum.reject(integer, &sign?/1)

    case split_groups(integer, reading) do
      [_ungrouped] -> :ok
      groups -> validate_groups(groups, reading.sizes, grouping)
    end
  end

  defp split_groups(tokens, reading) do
    tokens
    |> Enum.chunk_by(&group?(&1, reading))
    |> Enum.reject(fn [token | _] -> group?(token, reading) end)
    |> pad_empty_groups(tokens, reading)
  end

  # `chunk_by/2` drops nothing, but two separators side by side, or one
  # at either end, leave an empty group the reference's `String.split/2`
  # would report; count the separators to find them.
  defp pad_empty_groups(groups, tokens, reading) do
    separators = Enum.count(tokens, &group?(&1, reading))

    if length(groups) == separators + 1 do
      groups
    else
      groups ++ [[]]
    end
  end

  defp validate_groups(groups, sizes, grouping) do
    lengths = Enum.map(groups, &group_length/1)

    if Enum.all?(lengths, &is_integer/1) and grouped?(lengths, sizes, grouping) do
      :ok
    else
      {:error, :grouping}
    end
  end

  # A group that is not all digits is not a group at all.
  defp group_length([{:digits, digits, _source}]) do
    byte_size(digits)
  end

  defp group_length(_other) do
    nil
  end

  defp grouped?([leading | rest], {primary, secondary}, :lenient) do
    longest = max(primary, secondary)
    leading <= longest and Enum.all?(rest, &(&1 in @lenient_group_floor..longest//1))
  end

  # Each group is one the locale writes: the last of the primary size, the
  # ones before it of the primary or secondary size, and the first no
  # longer than either. So `de` refuses "1.23", which a two-digit floor
  # reads as 123 though it may well be 1.23, and `en-IN` takes both
  # "12,34,567" and "1,234,567".
  defp grouped?([leading | rest], {primary, secondary}, :sizes) do
    {last, middle} = List.pop_at(rest, -1)

    leading <= max(primary, secondary) and last == primary and
      Enum.all?(middle, &(&1 in [primary, secondary]))
  end

  defp grouped?([leading | rest], {primary, secondary}, :strict) do
    {last, middle} = List.pop_at(rest, -1)
    last == primary and Enum.all?(middle, &(&1 == secondary)) and leading <= secondary
  end

  # A period that is a separator of no reading is foreign to the locale,
  # and refused where any reading has one as a separator: `de-AT` groups
  # the euro with it, so its plain-number set, which does not, must not
  # take "1.23 EUR" for 1.23. Elsewhere one period between digits is a
  # decimal point, unless it has the shape of a thousands group: `fr`
  # "1.5" is 1.5, but "1.234" is refused.
  defp no_stray_period(body, reading, lexicon) do
    cond do
      reading.period? -> :ok
      not Enum.any?(body, &period?(&1, lexicon)) -> :ok
      lexicon.period_separator? -> {:error, :stray_period}
      foreign_decimal_point?(body, reading, lexicon) -> :ok
      true -> {:error, :stray_period}
    end
  end

  # Exactly one period, between digits, and no decimal mark of the
  # reading; not one to three digits, the period and three digits.
  defp foreign_decimal_point?(body, reading, lexicon) do
    not Enum.any?(body, &decimal?(&1, reading)) and
      Enum.count(body, &period?(&1, lexicon)) == 1 and
      period_between_digits?(body, lexicon) and
      not period_group?(body, lexicon)
  end

  defp period_between_digits?([{:digits, _, _}, period, {:digits, _, _} = next | rest], lexicon) do
    period?(period, lexicon) or period_between_digits?([next | rest], lexicon)
  end

  defp period_between_digits?([_token | rest], lexicon) do
    period_between_digits?(rest, lexicon)
  end

  defp period_between_digits?([], _lexicon) do
    false
  end

  defp period_group?([{:digits, leading, _}, period, {:digits, group, _} | _rest], lexicon) do
    byte_size(leading) in 1..3 and period?(period, lexicon) and byte_size(group) == 3
  end

  defp period_group?(_body, _lexicon) do
    false
  end

  # ── The number string ─────────────────────────────────────────

  # What each token contributes to the number Elixir parses: digits their
  # Latin value, a decimal mark a period, a group separator nothing, a sign
  # itself, and anything else its text, which the parse then refuses.
  defp token_text({:digits, digits, _source}, _reading) do
    digits
  end

  defp token_text({:minus, _value, _source}, _reading) do
    "-"
  end

  defp token_text({:plus, _value, _source}, _reading) do
    "+"
  end

  defp token_text({:space, _value, _source}, _reading) do
    ""
  end

  defp token_text({:mark, _value, source} = token, reading) do
    cond do
      decimal?(token, reading) -> "."
      group?(token, reading) -> ""
      true -> source
    end
  end

  defp token_text({_kind, _value, source}, _reading) do
    source
  end

  # A decimal point may open or close a number, ".5" or "5.". Elixir's
  # float and integer parsers refuse both and its decimal parser takes
  # them, so the point is completed here and every number type reads them
  # alike.
  defp complete_decimal_point(number) do
    number
    |> open_point()
    |> close_point()
  end

  defp open_point("." <> <<digit, _::binary>> = number) when digit in ?0..?9 do
    "0" <> number
  end

  defp open_point(number) do
    number
  end

  defp close_point(number) when byte_size(number) >= 2 do
    size = byte_size(number) - 2

    case number do
      <<_::binary-size(^size), digit, ?.>> when digit in ?0..?9 ->
        binary_part(number, 0, size + 1)

      _other ->
        number
    end
  end

  defp close_point(number) do
    number
  end

  defp signed(number, true) do
    "-" <> number
  end

  defp signed(number, false) do
    number
  end

  defp parse_number(string, nil) do
    with {:error, _} <- parse_number(string, :integer),
         {:error, _} <- parse_number(string, :float) do
      {:error, :not_a_number}
    end
  end

  defp parse_number(string, :integer) do
    case Integer.parse(string) do
      {integer, ""} -> {:ok, integer}
      _other -> {:error, :not_a_number}
    end
  end

  defp parse_number(string, :float) do
    case Float.parse(string) do
      {float, ""} -> {:ok, float}
      _other -> {:error, :not_a_number}
    end
  end

  defp parse_number(string, :decimal) do
    case Localize.Utils.Decimal.parse(string) do
      {decimal, ""} -> {:ok, decimal}
      _other -> {:error, :not_a_number}
    end
  end

  # A decimal whose exponent would make downstream operations expensive is
  # refused rather than returned to misbehave under multiplication or
  # formatting. Integers and floats are bounded by their own ranges.
  defp bound_decimal_exponent(%Decimal{exp: exp} = decimal, max_exponent)
       when is_integer(exp) and is_integer(max_exponent) do
    if abs(exp) > max_exponent do
      {:error, parse_error("Decimal exponent #{exp} exceeds limit of ±#{max_exponent}")}
    else
      {:ok, decimal}
    end
  end

  defp bound_decimal_exponent(value, _max_exponent) do
    {:ok, value}
  end

  # ── Tokens ────────────────────────────────────────────────────

  defp decimal?({:mark, _value, source}, reading) do
    MapSet.member?(reading.decimal, source)
  end

  defp decimal?(_token, _reading) do
    false
  end

  defp group?({:mark, _value, source}, reading) do
    MapSet.member?(reading.group, source)
  end

  defp group?({:space, _value, _source}, reading) do
    reading.space_group?
  end

  defp group?(_token, _reading) do
    false
  end

  defp period?({:mark, _value, source}, lexicon) do
    MapSet.member?(lexicon.period, source)
  end

  defp period?(_token, _lexicon) do
    false
  end

  defp space?({kind, _value, _source}) do
    kind == :space
  end

  defp sign?({kind, _value, _source}) do
    kind in [:minus, :plus]
  end

  defp dash?({kind, _value, _source}) do
    kind in [:minus, :dash]
  end

  defp digit?({kind, _value, _source}) do
    kind in [:digits, :other_digits]
  end

  defp drop_spaces(tokens) do
    Enum.drop_while(tokens, &space?/1)
  end

  defp take_sign([{kind, _value, _source} | rest]) when kind in [:minus, :plus] do
    {kind, rest}
  end

  defp take_sign(tokens) do
    {nil, tokens}
  end

  defp take_kind([{kind, _value, _source} = token | rest], kind) do
    {[token], rest}
  end

  defp take_kind(tokens, _kind) do
    {[], tokens}
  end

  # ── Errors ────────────────────────────────────────────────────

  defp parse_error(message) do
    Localize.InvalidValueError.exception(
      value: message,
      expected: "a parseable number string",
      context: "Localize.Number.Parser"
    )
  end

  defp ambiguous_number(string, value, other) do
    Localize.ParseError.exception(
      input: string,
      reason: :unexpected_input,
      detail: "it is ambiguous, #{number_text(value)} or #{number_text(other)}"
    )
  end

  defp number_text(%Decimal{} = decimal) do
    Decimal.to_string(decimal, :normal)
  end

  defp number_text(number) do
    to_string(number)
  end
end
