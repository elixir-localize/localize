defmodule Localize.Message.Parser do
  @moduledoc """
  Implements a parser for
  [ICU MessageFormat 2](https://unicode.org/reports/tr35/tr35-messageFormat.html).

  """

  import NimbleParsec
  import Localize.Message.Parser.Combinator

  defparsec(:message, message())

  @doc """
  Parses a MessageFormat 2 message string.

  ### Arguments

  * `input` is a MF2 message string.

  ### Returns

  * `{:ok, ast}` where `ast` is the parsed message AST.

  * `{:error, reason}` if the message cannot be parsed.

  ### Examples

      iex> Localize.Message.Parser.parse("{{Hello, world!}}")
      {:ok, [{:complex, [], {:quoted_pattern, [{:text, "Hello, world!"}]}}]}

  """
  @spec parse(String.t()) :: {:ok, list()} | {:error, String.t()}

  def parse(input) when is_binary(input) do
    case message(input) do
      {:ok, result, "", _, _, _} ->
        {:ok, result}

      {:ok, _result, rest, _, _, offset} ->
        {:error,
         "Could not parse the remaining #{inspect(rest)} starting at position #{offset + 1}"}

      {:error, reason, rest, _, _, offset} ->
        {:error,
         "#{reason}. Could not parse the remaining #{inspect(rest)} at position #{offset + 1}"}
    end
  end

  @doc """
  Parses a MessageFormat 2 message string, raising on error.

  Same as `parse/1` but returns the AST directly or raises
  `Localize.ParseError`.

  ### Arguments

  * `input` is a MF2 message string.

  ### Returns

  * The parsed message AST.

  ### Examples

      iex> Localize.Message.Parser.parse!("{{Hello, world!}}")
      [{:complex, [], {:quoted_pattern, [{:text, "Hello, world!"}]}}]

  """
  @spec parse!(String.t()) :: list() | no_return

  def parse!(input) when is_binary(input) do
    case parse(input) do
      {:ok, parsed} -> parsed
      {:error, reason} -> raise Localize.ParseError, input: input, reason: reason
    end
  end
end
