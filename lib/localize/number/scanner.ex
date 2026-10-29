defmodule Localize.Number.Scanner do
  @moduledoc """
  Scans a string into the numbers it holds and the text around
  them, from the tokens of `Localize.Number.Lexer`.

  The scanner walks the tokens once. At each token it takes the
  longest run that has the shape of a number below, and hands the run
  to `Localize.Number.Grammar`: the run is a number where the grammar
  reads one, and a piece of text of its own where it does not, since
  the grammar's rules are stricter than the shape. Everything else is
  text, returned as it was written, with consecutive pieces of text
  joined into one.

  ## Grammar

  ```ebnf
  scan      = { number | text } ;
  number    = bidi, [ sign, bidi ], integer, [ fraction ], [ exponent ] ;
  bidi      = { bidi-control } ;
  integer   = digits, { digits | "_" | group, digits } ;
  fraction  = decimal, zero-dash | decimal, { digits | "_" }- ;
  zero-dash = dash, [ dash ] ;
  exponent  = ( "e" | "E" ), [ sign ], digits ;
  ```

  `decimal` and `group` are the marks of the lexicon's first reading,
  the separators of the locale, the number system and the options in
  hand, and a space is a `group` where that reading groups with one.
  The shape is narrower than the grammar's: a sign comes only before
  the digits and touches them, there are no parentheses and no space
  inside the number, so `"- 5"` is text and a number and `"(5)"` three
  pieces. The rules that complete the shape are the named functions
  below:

  * a group separator is followed by a plausible group: two digits or
    more leniently, exactly the locale's group strictly
    (`plausible_group?/3`);

  * a decimal separator is followed by a digit, an underscore, or the
    dashes of a zero fraction, which are read leniently only
    (`fraction/2`, `zero_dash/2`);

  * a zero fraction is one or two dashes with no digit after them, and
    ends the number (`zero_dash/2`);

  * an exponent is an ASCII `e` or `E`, a sign and digits, after the
    integer or after a fraction written with digits (`exponent/1`);

  * a bidi control before the digits, or between the sign and the
    digits, is part of the number; one after the digits is text
    (`number_run/2`).

  """

  alias Localize.Number.{Grammar, Lexer, Lexicon}

  # The shortest group a lenient scan takes after a group separator: two
  # digits, the floor that keeps "3 4 5" three numbers where a space
  # groups.
  @lenient_group_floor 2

  # The tokens that may stand for a zero fraction's dash.
  @dash_kinds [:minus, :dash]

  @typep context :: %{
           lexicon: Lexicon.t(),
           reading: Lexicon.reading(),
           lenient?: boolean(),
           max_bytes: pos_integer() | nil,
           grammar: Keyword.t()
         }

  @doc """
  Scans a string into numbers and text with a lexicon.

  ### Arguments

  * `string` is the text to scan.

  * `lexicon` is the `t:Localize.Number.Lexicon.t/0` to scan it with.

  * `options` is a keyword list of options.

  ### Options

  * `:number` is the type to read each number as: `:integer`, `:float`,
    `:decimal`, or `nil` to read an integer where the text is one and
    a float otherwise.

  * `:grouping` is how the grammar checks group separators: `:lenient`,
    `:strict` or `:sizes`.

  * `:lenient` is `false` to take only groups of the locale's sizes and
    no zero fraction. The default is `true`.

  * `:max_number_bytes` is the longest run, in bytes, that is read as a
    number; a longer one is text. The default is no limit.

  * `:max_decimal_exponent` bounds the exponent of a decimal read.

  ### Returns

  * A list of strings and numbers.

  ### Examples

      iex> {:ok, fr} = Localize.validate_locale(:fr)
      iex> {:ok, lexicon} = Localize.Number.Lexicon.fetch(fr, :latn, [])
      iex> Localize.Number.Scanner.scan("2 000 et 3 000", lexicon, [])
      [2000, " et ", 3000]

      iex> {:ok, en} = Localize.validate_locale(:en)
      iex> {:ok, lexicon} = Localize.Number.Lexicon.fetch(en, :latn, [])
      iex> Localize.Number.Scanner.scan("v1.2.3 and 4,5", lexicon, [])
      ["v", 1.2, ".", 3, " and ", 4, ",", 5]

  """
  @spec scan(String.t(), Lexicon.t(), Keyword.t()) ::
          [String.t() | integer() | float() | Decimal.t()]
  def scan(string, %Lexicon{} = lexicon, options) when is_binary(string) do
    context = %{
      lexicon: lexicon,
      reading: hd(lexicon.readings),
      lenient?: Keyword.get(options, :lenient, true),
      max_bytes: Keyword.get(options, :max_number_bytes),
      grammar: Keyword.take(options, [:number, :grouping, :max_decimal_exponent])
    }

    string
    |> Lexer.tokens(lexicon)
    |> pieces(context, [], [])
  end

  # ── Pieces ────────────────────────────────────────────────────

  # The text pieces gather in `text`, newest first, until a number ends
  # them; the pieces gather in `out`, newest first.
  defp pieces([], _context, text, out) do
    text
    |> flush(out)
    |> Enum.reverse()
  end

  defp pieces([{_kind, _value, source} | rest] = tokens, context, text, out) do
    case number_run(tokens, context) do
      {run, after_run} -> read_run(run, after_run, context, text, out)
      :none -> pieces(rest, context, [source | text], out)
    end
  end

  # A run the grammar refuses is text as it was written, a piece of its
  # own rather than joined to the text around it, so that a caller can
  # still see the run.
  defp read_run(run, rest, context, text, out) do
    case read(run, context) do
      {:ok, number} -> pieces(rest, context, [], [number | flush(text, out)])
      :error -> pieces(rest, context, [], [source(run) | flush(text, out)])
    end
  end

  defp flush([], out) do
    out
  end

  defp flush(text, out) do
    [text |> Enum.reverse() |> IO.iodata_to_binary() | out]
  end

  defp source(tokens) do
    Enum.map_join(tokens, fn {_kind, _value, source} -> source end)
  end

  # A run longer than the byte cap is not read at all, as `parse/2`
  # refuses a string that long.
  defp read(run, context) do
    source = source(run)

    if too_long?(source, context.max_bytes) do
      :error
    else
      read_number(run, source, context)
    end
  end

  defp too_long?(_source, nil) do
    false
  end

  defp too_long?(source, max_bytes) do
    byte_size(source) > max_bytes
  end

  defp read_number(run, source, context) do
    case Grammar.read_tokens(run, source, context.lexicon, context.grammar) do
      {:ok, number} -> {:ok, number}
      {:error, _exception} -> :error
    end
  end

  # ── The shape of a number ─────────────────────────────────────

  # The longest run from the head of the tokens with the shape of a
  # number, and the tokens after it, or `:none` where the tokens do not
  # start with one. Bidi controls before the sign and between the sign
  # and the digits are part of the run, as CLDR writes them into the
  # signs of the right-to-left locales; one after the digits is not.
  @spec number_run([Lexer.token()], context()) :: {[Lexer.token()], [Lexer.token()]} | :none
  defp number_run(tokens, context) do
    {bidi, tokens} = Enum.split_while(tokens, &bidi?/1)
    {sign, tokens} = take_sign(tokens)
    {inner_bidi, tokens} = Enum.split_while(tokens, &bidi?/1)

    case tokens do
      [{:digits, _value, _source} = digits | rest] ->
        {integer, rest} = integer(rest, context, [digits])
        {fraction, rest, exponent?} = fraction(rest, context)
        {exponent, rest} = exponent(rest, exponent?)
        {bidi ++ sign ++ inner_bidi ++ Enum.reverse(integer) ++ fraction ++ exponent, rest}

      _no_digits ->
        :none
    end
  end

  # Digits and underscores continue the integer freely; a group separator
  # only with a plausible group after it. The integer gathers newest
  # first.
  defp integer([{kind, _value, _source} = token | rest], context, integer)
       when kind in [:digits, :underscore] do
    integer(rest, context, [token | integer])
  end

  defp integer([group, {:digits, _value, _source} = digits | rest] = tokens, context, integer) do
    if Grammar.group?(group, context.reading) and plausible_group?(digits, rest, context) do
      integer(rest, context, [digits, group | integer])
    else
      {integer, tokens}
    end
  end

  defp integer(tokens, _context, integer) do
    {integer, tokens}
  end

  # Leniently, a group is two digits or more, the floor that keeps "3 4 5"
  # three numbers where a space groups. Strictly it is the locale's
  # primary size, or its secondary size with another separator after it,
  # so `en-IN` takes "12,34,567" and `fr` refuses "1 23".
  defp plausible_group?({:digits, digits, _source}, _rest, %{lenient?: true}) do
    byte_size(digits) >= @lenient_group_floor
  end

  defp plausible_group?({:digits, digits, _source}, rest, context) do
    {primary, secondary} = context.reading.sizes
    size = byte_size(digits)
    size == primary or (size == secondary and group_next?(rest, context.reading))
  end

  defp group_next?([token | _rest], reading) do
    Grammar.group?(token, reading)
  end

  defp group_next?([], _reading) do
    false
  end

  # A decimal separator opens a fraction only with digits, underscores or
  # a zero fraction's dashes after it; otherwise it is not part of the
  # number. The third element says whether an exponent may follow: after
  # digits it may, after the dashes it may not.
  defp fraction([mark | rest] = tokens, context) do
    if Grammar.decimal?(mark, context.reading) do
      decimal_fraction(mark, rest, tokens, context)
    else
      {[], tokens, true}
    end
  end

  defp fraction([], _context) do
    {[], [], true}
  end

  defp decimal_fraction(mark, rest, tokens, context) do
    case zero_dash(rest, context.lenient?) do
      {dashes, after_dashes} -> {[mark | dashes], after_dashes, false}
      :none -> digit_fraction(mark, rest, tokens)
    end
  end

  defp digit_fraction(mark, rest, tokens) do
    case Enum.split_while(rest, &digit_or_underscore?/1) do
      {[], _rest} -> {[], tokens, true}
      {digits, after_digits} -> {[mark | digits], after_digits, true}
    end
  end

  # Swiss "5.–" and Dutch "5,-" write a zero fraction as one or two
  # dashes, read leniently only (CLDR-3394). A digit after the dashes
  # makes them no zero fraction: "1.-2" is 1, a period and -2; and two
  # dashes before a digit leave the second to the digit.
  defp zero_dash([{first_kind, _, _} = first, {second_kind, _, _} = second | rest], true)
       when first_kind in @dash_kinds and second_kind in @dash_kinds do
    if digits_next?(rest) do
      {[first], [second | rest]}
    else
      {[first, second], rest}
    end
  end

  defp zero_dash([{kind, _value, _source} = dash | rest], true) when kind in @dash_kinds do
    if digits_next?(rest) do
      :none
    else
      {[dash], rest}
    end
  end

  defp zero_dash(_tokens, _lenient?) do
    :none
  end

  # An exponent is an ASCII `e` or `E` standing alone, an optional sign
  # and digits. None follows a zero fraction.
  defp exponent(tokens, false) do
    {[], tokens}
  end

  defp exponent(
         [{:text, _, e} = marker, {kind, _, _} = sign, {:digits, _, _} = digits | rest],
         true
       )
       when e in ["e", "E"] and kind in [:minus, :plus] do
    {[marker, sign, digits], rest}
  end

  defp exponent([{:text, _, e} = marker, {:digits, _, _} = digits | rest], true)
       when e in ["e", "E"] do
    {[marker, digits], rest}
  end

  defp exponent(tokens, true) do
    {[], tokens}
  end

  # ── Tokens ────────────────────────────────────────────────────

  defp bidi?({kind, _value, _source}) do
    kind == :bidi
  end

  defp take_sign([{kind, _value, _source} = sign | rest]) when kind in [:minus, :plus] do
    {[sign], rest}
  end

  defp take_sign(tokens) do
    {[], tokens}
  end

  defp digits_next?([{:digits, _value, _source} | _rest]) do
    true
  end

  defp digits_next?(_tokens) do
    false
  end

  defp digit_or_underscore?({kind, _value, _source}) do
    kind in [:digits, :underscore]
  end
end
