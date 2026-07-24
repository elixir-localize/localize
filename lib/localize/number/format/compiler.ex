defmodule Localize.Number.Format.Compiler do
  @moduledoc """
  Compiles number format patterns into metadata for fast runtime
  interpretation.

  Number format patterns like `"#,##0.###"` or `"¤#,##0.00"` are
  parsed using a leex/yecc lexer-parser and then analysed to
  extract formatting metadata (digit counts, grouping, rounding,
  etc.) into a `Localize.Number.Format.Meta` struct.

  """

  import Kernel, except: [length: 1]
  alias Localize.Number.Format.Meta

  @decimal_separator "."
  @grouping_separator ","
  @significant_digit "@"
  @digit_omit_zeroes "#"
  @digits "[0-9]"
  @default_pad_char " "
  @default_round_nearest 0
  @max_integer_digits 0
  @min_integer_digits 1
  @min_fraction_digits 0

  @rounding_pattern "[" <> @digit_omit_zeroes <> @significant_digit <> @grouping_separator <> "]"

  # ── Placeholder symbols ──────────────────────────────────────

  @doc false
  def placeholder(:decimal), do: "."
  def placeholder(:group), do: ","
  def placeholder(:exponent), do: "E"
  def placeholder(:plus), do: "+"
  def placeholder(:minus), do: "-"
  def placeholder(:currency), do: "¤"
  def placeholder(:exponent_sign), do: "+"

  # ── Tokenize and parse ──────────────────────────────────────

  @doc """
  Tokenizes a number format definition string.

  ### Arguments

  * `definition` is a number format pattern string.

  ### Returns

  * `{:ok, tokens, end_line}` or an error tuple.

  ### Examples

      iex> Localize.Number.Format.Compiler.tokenize("0.00")
      {:ok, [{:format, 1, ~c"0.00"}], 1}

  """
  @spec tokenize(String.t()) :: {:ok, list(), integer()} | {:error, term(), integer()}
  def tokenize(definition) when is_binary(definition) do
    definition
    |> String.to_charlist()
    |> :localize_decimal_formats_lexer.string()
  end

  @doc """
  Parses a number format definition into a keyword list of
  positive and negative format elements.

  ### Arguments

  * `definition` is a number format pattern string or a
    list of tokens from `tokenize/1`.

  ### Returns

  * `{:ok, format}` where `format` is a keyword list with
    `:positive` and `:negative` keys.

  * `{:error, reason}` if parsing fails.

  ### Examples

      iex> {:ok, parsed} = Localize.Number.Format.Compiler.parse("#,##0.###")
      iex> parsed[:positive]
      [format: "#,##0.###"]

  """
  @spec parse(String.t() | list()) :: {:ok, Keyword.t()} | {:error, term()}
  def parse(tokens) when is_list(tokens) do
    :localize_decimal_formats_parser.parse(tokens)
  end

  def parse("") do
    {:error, "empty format string cannot be compiled"}
  end

  def parse(definition) when is_binary(definition) do
    {:ok, tokens, _end_line} = tokenize(definition)
    :localize_decimal_formats_parser.parse(tokens)
  end

  def parse(nil) do
    {:error, "no format string or token list provided"}
  end

  # ── Compile ──────────────────────────────────────────────────

  @doc """
  Compiles a number format definition into metadata.

  Parses the format string, analyses it, and returns the
  metadata struct used to drive number formatting.

  ### Arguments

  * `definition` is a number format pattern string.

  ### Returns

  * `{:ok, meta}` where `meta` is a `Localize.Number.Format.Meta.t()`.

  * `{:error, reason}` if parsing fails.

  ### Examples

      iex> {:ok, meta} = Localize.Number.Format.Compiler.compile("#,##0.###")
      iex> meta.fractional_digits
      %{min: 0, max: 3}
      iex> meta.grouping
      %{integer: %{first: 3, rest: 3}, fraction: %{first: 0, rest: 0}}

  """
  @spec compile(String.t()) :: {:ok, Meta.t()} | {:error, String.t()}
  def compile(definition) when is_binary(definition) do
    with {:ok, format} <- parse(definition),
         {:ok, meta_data} <- format_to_metadata(format) do
      {:ok, meta_data}
    else
      {:error, {_line, _parser, [message, context]}} ->
        {:error, "Decimal format compiler: #{message}#{Enum.join(context)}"}

      {:error, message} ->
        {:error, message}
    end
  end

  @doc """
  Extracts metadata from a parsed format.

  ### Arguments

  * `format` is either a format pattern string or a parsed
    keyword list from `parse/1`.

  ### Returns

  * `{:ok, meta}` where `meta` is a `Localize.Number.Format.Meta.t()`.

  ### Examples

      iex> {:ok, meta} = Localize.Number.Format.Compiler.format_to_metadata("0.00")
      iex> meta.fractional_digits
      %{min: 2, max: 2}

  """
  @spec format_to_metadata(String.t() | Keyword.t()) :: {:ok, Meta.t()} | {:error, String.t()}
  def format_to_metadata(format) when is_binary(format) do
    case parse(format) do
      {:ok, parsed} ->
        format_to_metadata(parsed)

      {:error, {_line, _parser, [message, context]}} ->
        {:error, "Decimal format compiler: #{message}#{Enum.join(context)}"}

      {:error, reason} when is_binary(reason) ->
        {:error, reason}
    end
  end

  def format_to_metadata(format) when is_list(format) do
    metadata = analyse(format, format[:positive][:format])

    case validate_scientific_constraints(metadata) do
      :ok -> {:ok, metadata}
      {:error, _} = error -> error
    end
  end

  @doc """
  Same as `format_to_metadata/1` but raises on error.

  ### Arguments

  * `format` is either a format pattern string or a parsed
    keyword list.

  ### Returns

  * A `Localize.Number.Format.Meta.t()` struct.

  ### Raises

  * Raises `ArgumentError` if the format cannot be parsed.

  ### Examples

      iex> meta = Localize.Number.Format.Compiler.format_to_metadata!("#,##0.###")
      iex> meta.integer_digits
      %{min: 1, max: 0}

  """
  @spec format_to_metadata!(String.t() | Keyword.t()) :: Meta.t()
  def format_to_metadata!(format) do
    case format_to_metadata(format) do
      {:ok, metadata} -> metadata
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Returns a regex that can be used to split a number format
  or number string into integer, fraction, and exponent parts.

  ### Returns

  * A `t:Regex.t/0` with the named captures `integer`, `fraction`,
    `exponent_sign`, and `exponent_digits`.

  ### Examples

      iex> regex = Localize.Number.Format.Compiler.number_match_regex()
      iex> Regex.named_captures(regex, "1234.567")["fraction"]
      "567"

  """
  @integer_digits "(?<integer>[@#0-9,]+)"
  @fraction_digits "([.](?<fraction>[#0-9,]+))?"
  @exponent "([Ee](?<exponent_sign>[+-])?(?<exponent_digits>[0-9]+))?"
  @format_regex @integer_digits <> @fraction_digits <> @exponent

  @spec number_match_regex() :: Regex.t()
  def number_match_regex do
    format_re()
  end

  # ── Analysis ─────────────────────────────────────────────────

  defp analyse(format, positive_format) do
    format_parts = split_format(positive_format)

    min_int = required_integer_digits(format_parts)
    max_int = max_integer_digits(format_parts)

    meta = %Meta{
      integer_digits: %{min: min_int, max: max_int},
      fractional_digits: %{
        min: required_fraction_digits(format_parts),
        max: optional_fraction_digits(format_parts) + required_fraction_digits(format_parts)
      },
      significant_digits: significant_digits(format_parts),
      exponent_digits: exponent_digits(format_parts),
      exponent_sign: exponent_sign(format_parts),
      engineering_grouping: engineering_grouping(format_parts, min_int, max_int),
      scientific_rounding: scientific_rounding(format_parts),
      grouping: grouping(format_parts),
      round_nearest: round_nearest(format_parts),
      padding_length: padding_length(format[:positive][:pad], format),
      padding_char: padding_char(format),
      multiplier: multiplier(format),
      currency: currency_location(format[:positive]),
      format: format
    }

    reconcile_significant_and_scientific_digits(meta)
  end

  # ── Format splitting ─────────────────────────────────────────

  defp split_format(nil), do: %{}

  defp split_format(format) do
    parts = Regex.named_captures(format_re(), format)

    parts
    |> Map.put("compact_integer", String.replace(parts["integer"], @grouping_separator, ""))
    |> Map.put("compact_fraction", String.replace(parts["fraction"], @grouping_separator, ""))
  end

  # ── Integer digit extraction ────────────────────────────────

  @digits_match "(?<digits>" <> @digits <> "+)"

  defp required_integer_digits(%{"compact_integer" => integer_format}) do
    if captures = Regex.named_captures(digits_re(), integer_format) do
      String.length(captures["digits"])
    else
      @min_integer_digits
    end
  end

  defp required_integer_digits(_), do: @min_integer_digits

  # For non-scientific patterns we leave `max_integer_digits` at 0 — the
  # sentinel meaning "no upper limit", consumed by the formatter's
  # `set_max_integer_digits/2` (see `Localize.Number.Formatter.Decimal`).
  #
  # For scientific patterns (`E` present) TR35 uses the count of integer
  # placeholders in the pattern to drive both the mantissa width and the
  # engineering grouping. For `0.###E0` it is 1 (scientific); for
  # `##0.###E0` it is 3 (engineering with exponent ≡ 0 mod 3); for
  # `00.###E0` it is 2 (fixed-width mantissa, exponent shift = min - 1).
  #
  # Significant-digit patterns (`@@##E0`) are handled by
  # `reconcile_significant_and_scientific_digits/1` after analysis; we do
  # not count `@` placeholders here because TR35 forces those to a
  # 1-integer-digit mantissa regardless of the `@` count.
  defp max_integer_digits(format_parts) do
    cond do
      exponent_digits(format_parts) == 0 -> @max_integer_digits
      has_significant_placeholder?(format_parts) -> @max_integer_digits
      true -> pattern_integer_placeholder_count(format_parts)
    end
  end

  defp has_significant_placeholder?(%{"compact_integer" => integer_format})
       when is_binary(integer_format) do
    String.contains?(integer_format, @significant_digit)
  end

  defp has_significant_placeholder?(_), do: false

  defp pattern_integer_placeholder_count(%{"compact_integer" => integer_format})
       when is_binary(integer_format) do
    String.length(integer_format)
  end

  defp pattern_integer_placeholder_count(_), do: 0

  # TR35 engineering rule (one sentence): when `maxIntegerDigits >
  # minIntegerDigits`, the exponent is forced to a multiple of
  # `maxIntegerDigits`. Otherwise the format is pure scientific (mantissa
  # has exactly `minIntegerDigits` integer digits) and no grouping
  # constraint applies, so we return 0.
  defp engineering_grouping(format_parts, min_int, max_int) do
    cond do
      exponent_digits(format_parts) == 0 -> 0
      max_int > min_int -> max_int
      true -> 0
    end
  end

  # ── Fraction digit extraction ───────────────────────────────

  defp required_fraction_digits(%{"compact_fraction" => nil}), do: 0

  defp required_fraction_digits(%{"compact_fraction" => fraction_format}) do
    if captures = Regex.named_captures(digits_re(), fraction_format) do
      String.length(captures["digits"])
    else
      @min_fraction_digits
    end
  end

  defp required_fraction_digits(_), do: @min_fraction_digits

  @hashes_match "(?<hashes>[" <> @digit_omit_zeroes <> "]+)"

  defp optional_fraction_digits(%{"compact_fraction" => ""}), do: 0

  defp optional_fraction_digits(%{"compact_fraction" => fraction_format}) do
    if captures = Regex.named_captures(hashes_re(), fraction_format) do
      String.length(captures["hashes"])
    else
      0
    end
  end

  defp optional_fraction_digits(_), do: 0

  # ── Exponent extraction ────────────────────────────────────

  defp exponent_digits(%{"exponent_digits" => ""}), do: 0
  defp exponent_digits(%{"exponent_digits" => exp}), do: String.length(exp)
  defp exponent_digits(_), do: 0

  @doc false
  def exponent_sign(%{"exponent_sign" => ""}), do: false
  def exponent_sign(%{"exponent_sign" => _}), do: true
  def exponent_sign(_), do: false

  # ── Scientific rounding ────────────────────────────────────

  @scientific_match "(?<scientific_rounding>0[0#]*)?"

  defp scientific_rounding(%{"exponent_digits" => ""}), do: 0

  defp scientific_rounding(%{
         "compact_integer" => integer_format,
         "compact_fraction" => fraction_format
       }) do
    format = integer_format <> fraction_format

    if captures = Regex.named_captures(scientific_re(), format) do
      String.length(captures["scientific_rounding"])
    else
      0
    end
  end

  defp scientific_rounding(_), do: 0

  # ── Grouping extraction ────────────────────────────────────

  defp grouping(%{"integer" => integer_format, "fraction" => fraction_format}) do
    %{integer: integer_grouping(integer_format), fraction: fraction_grouping(fraction_format)}
  end

  defp grouping(_) do
    %{
      integer: %{first: @max_integer_digits, rest: @max_integer_digits},
      fraction: %{first: @max_integer_digits, rest: @max_integer_digits}
    }
  end

  defp integer_grouping(format) do
    [_drop | groups] = String.split(format, @grouping_separator)

    grouping =
      groups
      |> Enum.reverse()
      |> Enum.slice(0..1)
      |> Enum.map(&String.length/1)

    case grouping do
      [first, rest] -> %{first: first, rest: rest}
      [first] -> %{first: first, rest: first}
      _ -> %{first: @max_integer_digits, rest: @max_integer_digits}
    end
  end

  defp fraction_grouping(format) do
    case String.split(format, @grouping_separator) do
      [_] -> %{first: @max_integer_digits, rest: @max_integer_digits}
      [group | _] -> %{first: String.length(group), rest: String.length(group)}
    end
  end

  # ── Significant digits ─────────────────────────────────────

  @min_significant_digits "(?<ats>" <> @significant_digit <> "+)"
  @max_significant_digits "(?<hashes>" <> @digit_omit_zeroes <> "*)?"
  @leading_digits "([" <> @digit_omit_zeroes <> @grouping_separator <> "]*)?"
  @significant_digits_match @leading_digits <> @min_significant_digits <> @max_significant_digits

  defp significant_digits(%{
         "compact_integer" => integer_format,
         "compact_fraction" => fraction_format
       }) do
    format = integer_format <> fraction_format

    if captures = Regex.named_captures(significant_re(), format) do
      minimum = String.length(captures["ats"])
      maximum = minimum + String.length(captures["hashes"])
      %{min: minimum, max: maximum}
    else
      %{min: 0, max: 0}
    end
  end

  defp significant_digits(_), do: %{min: 0, max: 0}

  # ── Rounding ───────────────────────────────────────────────

  defp round_nearest(%{"integer" => integer_format, "fraction" => fraction_format}) do
    format =
      (integer_format <> @decimal_separator <> fraction_format)
      |> String.replace(rounding_re(), "")
      |> String.trim_trailing(@decimal_separator)

    case Float.parse(format) do
      :error -> @default_round_nearest
      {rounding, ""} -> rounding
    end
  end

  defp round_nearest(_), do: @default_round_nearest

  # ── Padding ────────────────────────────────────────────────

  defp padding_length(nil, _format), do: 0

  defp padding_length(_pad, format) do
    String.length(format[:positive][:format])
  end

  @doc false
  def padding_char(format) do
    format[:positive][:pad] || @default_pad_char
  end

  # ── Multiplier ─────────────────────────────────────────────

  defp multiplier(format) do
    cond do
      Keyword.has_key?(format[:positive], :percent) -> 100
      Keyword.has_key?(format[:positive], :permille) -> 1000
      true -> 1
    end
  end

  # ── Currency location ──────────────────────────────────────

  defp currency_location([{:currency, count} | _rest]) do
    %{location: :first, symbol_count: count}
  end

  defp currency_location(parts) do
    location =
      Enum.reduce_while(parts, 0, fn
        {:currency, count}, offset -> {:halt, %{location: offset, symbol_count: count}}
        _other, offset -> {:cont, offset + 1}
      end)

    if location == 0 do
      nil
    else
      adjust_location(location, Kernel.length(parts))
    end
  end

  defp adjust_location(%{location: offset} = location, count) when count == offset + 1 do
    %{location | location: :last}
  end

  defp adjust_location(location, _count), do: location

  # ── Scientific-pattern validation ──────────────────────────

  # TR35 forbids grouping separators in scientific patterns:
  # `#,##0.###E0` is a malformed format. The grouping decision is
  # made on the mantissa (which has only `min..max` integer digits,
  # at most), so the comma is silently ignored at output time and the
  # result is misleading. Reject these patterns at compile time with a
  # clear error so the caller can fix the pattern rather than
  # debugging a wrong value at runtime.
  #
  # **Breaking change in 0.41.0.** Patterns like `#,##0.###E0` that
  # previously silently round-tripped to the no-grouping form will now
  # return `{:error, …}` from `Localize.Number.to_string/2`.
  defp validate_scientific_constraints(%Meta{exponent_digits: 0}), do: :ok

  defp validate_scientific_constraints(%Meta{
         exponent_digits: e,
         grouping: %{integer: %{first: first}}
       })
       when e > 0 and first > 0 do
    {:error,
     "Scientific number patterns must not contain a grouping separator. " <>
       "TR35 disallows grouping in scientific patterns because the mantissa " <>
       "never has enough integer digits to trigger a group; the separator is " <>
       "silently ignored at output time and the result is misleading. " <>
       "Remove the comma from the pattern, or use a non-scientific pattern."}
  end

  defp validate_scientific_constraints(_meta), do: :ok

  # ── Reconciliation ──────────────────────────────────────────

  # TR35 significant-digit scientific patterns. Per the spec, `@@###E0`
  # is equivalent to `0.0###E0` with the integer part fixed at 1 digit
  # and the fraction width = (max_sig - 1). Apply the canonical
  # transformation here so the runtime formatter — which already
  # handles `integer_digits`, `fractional_digits`, and
  # `scientific_rounding` — does not need a separate `@`-aware branch.
  #
  #   integer_digits       → %{min: 1, max: 1}
  #   fractional_digits    → %{min: min_sig - 1, max: max_sig - 1}
  #   significant_digits   → cleared (so `round_to_significant_digits/2`
  #                          is a no-op; mantissa rounding flows via
  #                          `scientific_rounding`)
  #   engineering_grouping → 0 (max == min, no engineering shift)
  #   scientific_rounding  → max_sig (the TR35 "n+1 significant digits"
  #                          rule, where n is max fraction = max_sig - 1)
  defp reconcile_significant_and_scientific_digits(%Meta{} = meta) do
    if meta.significant_digits[:min] > 0 && meta.exponent_digits > 0 do
      min_sig = meta.significant_digits[:min]
      max_sig = meta.significant_digits[:max]

      %{
        meta
        | integer_digits: %{min: 1, max: 1},
          fractional_digits: %{min: max(min_sig - 1, 0), max: max(max_sig - 1, 0)},
          significant_digits: %{min: 0, max: 0},
          engineering_grouping: 0,
          scientific_rounding: max_sig
      }
    else
      meta
    end
  end

  # ── Compiled regexes ────────────────────────────────────────
  #
  # These patterns are composed from module attributes, so they cannot
  # be written as `~r//` sigil literals, and on OTP 29 a compiled regex
  # cannot be stored as a module-attribute constant either. The
  # interpolating sigil `~r/#{@attr}/` recompiles the pattern on every
  # call, which dominated `format_to_metadata/1` (Regex.compile is
  # ~1-2us each, and `analyse/2` runs eight of them). They are instead
  # compiled once into `:persistent_term` — at supervisor start via
  # `precompile_regexes/0`, while the term table is still small — and
  # read on every use. A direct caller that skips application start
  # falls back to a one-time lazy compile.
  @regex_sources %{
    format: @format_regex,
    digits: @digits_match,
    hashes: @hashes_match,
    scientific: @scientific_match,
    significant: @significant_digits_match,
    rounding: @rounding_pattern
  }

  @doc false
  @spec precompile_regexes() :: :ok
  def precompile_regexes do
    Enum.each(@regex_sources, fn {key, source} ->
      :persistent_term.put({__MODULE__, :regex, key}, Regex.compile!(source))
    end)
  end

  defp format_re, do: regex(:format)
  defp digits_re, do: regex(:digits)
  defp hashes_re, do: regex(:hashes)
  defp scientific_re, do: regex(:scientific)
  defp significant_re, do: regex(:significant)
  defp rounding_re, do: regex(:rounding)

  defp regex(key) do
    case :persistent_term.get({__MODULE__, :regex, key}, nil) do
      nil ->
        compiled = Regex.compile!(Map.fetch!(@regex_sources, key))
        :persistent_term.put({__MODULE__, :regex, key}, compiled)
        compiled

      compiled ->
        compiled
    end
  end
end
