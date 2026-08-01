defmodule Localize.ParseError do
  @moduledoc """
  Exception raised when a language tag, unit identifier, or MF2 message
  cannot be parsed.

  For MF2 message parse errors, the exception carries structured source
  location information (`:offset`, `:line`, `:column`) describing where
  in the input the parser failed. `:line` and `:column` are 1-indexed
  and `:offset` is a 0-indexed byte offset into the input string. This
  information is intended for tooling — editor integrations, language
  servers, and CLI diagnostics — that need to map errors back to source
  positions.

  For other uses (language tag / unit identifier parsing) the location
  fields may be `nil`.

  The `:reason` field is a documented atom describing the parser
  failure category. The `:detail` field optionally carries additional
  context (for example, a NimbleParsec expectation string) and
  `:cause` carries an underlying exception when a higher-level parser
  has wrapped a lower-level one.

  When `:reason` is `:input_too_large` the parse was refused before it
  began because the input exceeded a configured byte cap. `:size` and
  `:limit` carry the byte counts and `:detail` names what was being
  parsed. `:input` is `nil` in this case — retaining the oversized
  string is the thing the cap exists to prevent.

  """

  @behaviour Localize.Exception

  defexception [:input, :reason, :offset, :line, :column, :rest, :detail, :cause, :size, :limit]

  @type reason ::
          :unexpected_trailing_input
          | :unexpected_input
          | :incomplete_input
          | :invalid_message_format
          | :input_too_large

  @type t :: %__MODULE__{
          input: String.t() | nil,
          reason: reason() | nil,
          offset: non_neg_integer() | nil,
          line: pos_integer() | nil,
          column: pos_integer() | nil,
          rest: String.t() | nil,
          detail: String.t() | nil,
          cause: Exception.t() | nil,
          size: non_neg_integer() | nil,
          limit: non_neg_integer() | nil
        }

  @impl Localize.Exception
  def reason_atoms,
    do: [
      :unexpected_trailing_input,
      :unexpected_input,
      :incomplete_input,
      :invalid_message_format,
      :input_too_large
    ]

  @impl true
  def exception(bindings) when is_list(bindings) do
    bindings = Keyword.merge(bindings, compute_location(bindings))
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{
        reason: :unexpected_trailing_input,
        input: input,
        rest: rest,
        line: line,
        column: column
      })
      when is_integer(line) and is_integer(column) do
    Localize.Exception.safe_message(
      "message",
      "Could not parse {$input} at line {$line} column {$column}: unexpected trailing input {$rest}",
      input: inspect(input),
      line: line,
      column: column,
      rest: inspect(rest)
    )
  end

  def message(%__MODULE__{
        reason: :unexpected_trailing_input,
        input: input,
        rest: rest,
        offset: offset
      })
      when is_integer(offset) do
    Localize.Exception.safe_message(
      "message",
      "Could not parse {$input} at position {$position}: unexpected trailing input {$rest}",
      input: inspect(input),
      position: offset + 1,
      rest: inspect(rest)
    )
  end

  def message(%__MODULE__{reason: :unexpected_trailing_input, input: input, rest: rest}) do
    Localize.Exception.safe_message(
      "message",
      "Could not parse {$input}: unexpected trailing input {$rest}",
      input: inspect(input),
      rest: inspect(rest)
    )
  end

  def message(%__MODULE__{
        reason: :unexpected_input,
        input: input,
        rest: rest,
        detail: detail,
        line: line,
        column: column
      })
      when is_integer(line) and is_integer(column) do
    Localize.Exception.safe_message(
      "message",
      "Could not parse {$input} at line {$line} column {$column}: {$detail}{$tail}",
      input: inspect(input),
      line: line,
      column: column,
      detail: detail_or_default(detail),
      tail: rest_suffix(rest)
    )
  end

  def message(%__MODULE__{
        reason: :unexpected_input,
        input: input,
        rest: rest,
        detail: detail,
        offset: offset
      })
      when is_integer(offset) do
    Localize.Exception.safe_message(
      "message",
      "Could not parse {$input} at position {$position}: {$detail}{$tail}",
      input: inspect(input),
      position: offset + 1,
      detail: detail_or_default(detail),
      tail: rest_suffix(rest)
    )
  end

  def message(%__MODULE__{reason: :unexpected_input, input: input, rest: rest, detail: detail}) do
    Localize.Exception.safe_message(
      "message",
      "Could not parse {$input}: {$detail}{$tail}",
      input: inspect(input),
      detail: detail_or_default(detail),
      tail: rest_suffix(rest)
    )
  end

  # The oversized input is deliberately not retained on the struct — it
  # is the thing we refused to hold. `:size` and `:limit` carry the byte
  # counts and `:detail` names what was being parsed.
  def message(%__MODULE__{reason: :input_too_large, size: size, limit: limit, detail: detail})
      when is_integer(size) and is_integer(limit) do
    Localize.Exception.safe_message(
      "message",
      "The {$detail} is {$size} bytes, which exceeds the configured maximum of {$limit} bytes",
      detail: detail_or_default(detail, "input"),
      size: size,
      limit: limit
    )
  end

  def message(%__MODULE__{reason: :incomplete_input, input: input}) do
    Localize.Exception.safe_message(
      "message",
      "Could not parse {$input}: input ended unexpectedly",
      input: inspect(input)
    )
  end

  def message(%__MODULE__{reason: :invalid_message_format, input: input, detail: detail}) do
    Localize.Exception.safe_message(
      "message",
      "Could not parse {$input}: {$detail}",
      input: inspect(input),
      detail: detail_or_default(detail)
    )
  end

  def message(%__MODULE__{input: input, detail: detail}) when is_binary(detail) do
    Localize.Exception.safe_message(
      "message",
      "Could not parse {$input}: {$detail}",
      input: inspect(input),
      detail: detail
    )
  end

  def message(%__MODULE__{input: input}) do
    Localize.Exception.safe_message(
      "message",
      "Could not parse {$input}",
      input: inspect(input)
    )
  end

  defp detail_or_default(nil), do: ""
  defp detail_or_default(detail) when is_binary(detail), do: detail

  defp detail_or_default(nil, default), do: default
  defp detail_or_default(detail, _default) when is_binary(detail), do: detail

  defp rest_suffix(nil), do: ""
  defp rest_suffix(""), do: ""
  defp rest_suffix(rest) when is_binary(rest), do: " (remaining: #{inspect(rest)})"

  @doc """
  Computes 1-indexed line and column for a byte offset into `input`.

  ### Arguments

  * `input` is the source string.

  * `offset` is a 0-indexed byte offset into `input`.

  ### Returns

  * `{line, column}` where both are 1-indexed positive integers.

  * If `offset` is out of bounds, returns the position of the last
    character (or `{1, 1}` for an empty input).

  ### Examples

      iex> Localize.ParseError.line_column("Hello\\nworld", 0)
      {1, 1}

      iex> Localize.ParseError.line_column("Hello\\nworld", 6)
      {2, 1}

      iex> Localize.ParseError.line_column("Hello\\nworld", 9)
      {2, 4}

  """
  @spec line_column(String.t(), non_neg_integer()) :: {pos_integer(), pos_integer()}
  def line_column(input, offset) when is_binary(input) and is_integer(offset) and offset >= 0 do
    # Clamp the offset to the byte length of the input so we never walk past the end.
    offset = min(offset, byte_size(input))
    <<prefix::binary-size(^offset), _rest::binary>> = input

    # Line is 1 plus the number of LF characters in the prefix. Column is
    # the number of graphemes after the last LF (or from start if none),
    # plus 1.
    line = 1 + count_newlines(prefix)

    column =
      case :binary.matches(prefix, "\n") do
        [] ->
          String.length(prefix) + 1

        matches ->
          {last_lf, 1} = List.last(matches)
          tail = binary_part(prefix, last_lf + 1, byte_size(prefix) - last_lf - 1)
          String.length(tail) + 1
      end

    {line, column}
  end

  @doc false
  # Called from `exception/1` to fill in `:line` and `:column` from
  # `:input` and `:offset` when those are supplied but the caller hasn't
  # provided explicit line/column values.
  defp compute_location(bindings) do
    input = Keyword.get(bindings, :input)
    offset = Keyword.get(bindings, :offset)

    if is_binary(input) and is_integer(offset) and not Keyword.has_key?(bindings, :line) do
      {line, column} = line_column(input, offset)
      [line: line, column: column]
    else
      []
    end
  end

  defp count_newlines(binary) do
    binary
    |> :binary.matches("\n")
    |> length()
  end
end
