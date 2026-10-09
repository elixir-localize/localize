defmodule Localize.DateTime.ParseOptions do
  @moduledoc false

  # Argument checks shared by the public parse functions. They take
  # untrusted input, so anything other than a string with a keyword list
  # of well-formed options returns an error rather than raising.

  @as_values [:struct, :map]

  @default_max_parse_length 1_024

  @doc """
  Validates the input and options passed to a parse function.

  ### Arguments

  * `input` is the value to be parsed.

  * `options` is the options argument passed to the parse function.

  ### Returns

  * `:ok` when `input` is a string and the options are well formed.

  * `{:error, exception}`, a `t:Localize.InvalidValueError.t/0`, where `input`
    is no string or the options are not well formed, and a
    `t:Localize.DateTimeParseLengthError.t/0` where the text is longer than
    `max_parse_length/0`.

  ### Examples

      iex> Localize.DateTime.ParseOptions.validate("May 5, 2026", locale: :en)
      :ok

      iex> {:error, %Localize.InvalidValueError{value: :bogus}} =
      ...>   Localize.DateTime.ParseOptions.validate("May 5, 2026", as: :bogus)

  """
  @spec validate(term(), term()) ::
          :ok
          | {:error, Localize.InvalidValueError.t() | Localize.DateTimeParseLengthError.t()}
  def validate(input, options) do
    with :ok <- validate_input(input),
         :ok <- validate_options(options),
         :ok <- validate_as(Keyword.get(options, :as, :struct)) do
      validate_reference_date(Keyword.get(options, :reference_date))
    end
  end

  # A binary that is not UTF-8 is no string at all, and the parsers' Unicode
  # regular expressions raise on it rather than fail to match.
  #
  # Length is checked here because reading a date and time tries each place
  # the text could divide into a date half and a time half: the divisions
  # grow with the text and each is read over text that grows with it too, so
  # the work grows with the square of the length. A date and time is bounded
  # — 329 bytes for the longest any locale writes, 666 for an interval of two
  # — so text past `max_parse_length/0` is refused rather than read.
  defp validate_input(input) when is_binary(input) do
    cond do
      not String.valid?(input) ->
        invalid(input, "a UTF-8 string to parse")

      byte_size(input) > max_parse_length() ->
        {:error,
         Localize.DateTimeParseLengthError.exception(
           input_length: byte_size(input),
           max_length: max_parse_length()
         )}

      true ->
        :ok
    end
  end

  defp validate_input(input), do: invalid(input, "a string to parse")

  defp validate_options(options) do
    if is_list(options) and Keyword.keyword?(options) do
      :ok
    else
      invalid(options, "a keyword list of options")
    end
  end

  defp validate_as(as) when as in @as_values, do: :ok

  defp validate_as(as) do
    {:error,
     Localize.InvalidValueError.exception(
       value: as,
       expected: :as_option,
       allowed_values: @as_values
     )}
  end

  # Only the year of the reference date is read, so any date-like value
  # carrying an integer year will do.
  defp validate_reference_date(nil), do: :ok
  defp validate_reference_date(%{year: year}) when is_integer(year), do: :ok
  defp validate_reference_date(other), do: invalid(other, "a date for :reference_date")

  defp invalid(value, expected) do
    {:error, Localize.InvalidValueError.exception(value: value, expected: expected)}
  end

  @doc """
  Returns the greatest length of text a parse function reads, in bytes.

  The default is 1,024 bytes, against the 666 bytes of the longest text any
  locale writes for an interval of two zoned date-times. Raise it where
  longer text has to be read, knowing that reading a date and time costs the
  square of the text's length:

      config :localize, :max_parse_length, 4_096

  ### Returns

  * The bound, in bytes.

  ### Examples

      iex> Localize.DateTime.ParseOptions.max_parse_length()
      1024

  """
  @spec max_parse_length() :: pos_integer()
  def max_parse_length do
    Application.get_env(:localize, :max_parse_length, @default_max_parse_length)
  end
end
