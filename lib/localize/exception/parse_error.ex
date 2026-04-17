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

  """

  defexception [:input, :reason, :offset, :line, :column, :rest]

  @type t :: %__MODULE__{
          input: String.t() | nil,
          reason: String.t() | nil,
          offset: non_neg_integer() | nil,
          line: pos_integer() | nil,
          column: pos_integer() | nil,
          rest: String.t() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    bindings = Keyword.merge(bindings, compute_location(bindings))
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{input: input, reason: reason, line: line, column: column})
      when is_integer(line) and is_integer(column) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "message",
      "Could not parse {$input} at line {$line} column {$column}: {$reason}",
      input: inspect(input),
      line: line,
      column: column,
      reason: reason
    )
  end

  def message(%__MODULE__{input: input, reason: reason}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "language_tag",
      "Could not parse {$input}: {$reason}",
      input: inspect(input),
      reason: reason
    )
  end

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

    cond do
      is_binary(input) and is_integer(offset) and not Keyword.has_key?(bindings, :line) ->
        {line, column} = line_column(input, offset)
        [line: line, column: column]

      true ->
        []
    end
  end

  defp count_newlines(binary) do
    binary
    |> :binary.matches("\n")
    |> length()
  end
end
