defmodule Localize.DateTime.Format.Compiler do
  @moduledoc false

  # Tokenizes date, time, and datetime format pattern strings
  # into a list of tokens suitable for the runtime formatter.
  #
  # Format strings follow the CLDR date field symbol table
  # described at http://unicode.org/reports/tr35/tr35-dates.html
  #
  # # tokenize/1
  #
  # Tokenizes a format pattern string.
  #
  # ### Arguments
  #
  # * `format_string` is a CLDR date/time format pattern string.
  #
  # ### Returns
  #
  # * `{:ok, token_list, end_line}` on success.
  #
  # * `{:error, exception}` on failure.
  #
  # ### Examples
  #
  #     iex> Localize.DateTime.Format.Compiler.tokenize("yyyy/MM/dd")
  #     {:ok,
  #      [{:year, 1, 4}, {:literal, 1, "/"}, {:month, 1, 2}, {:literal, 1, "/"},
  #       {:day_of_month, 1, 2}], 1}

  @spec tokenize(String.t()) ::
          {:ok, [{atom(), integer(), integer() | String.t()}], integer()}
          | {:error, Exception.t()}
  def tokenize(format_string) when is_binary(format_string) do
    format_string
    |> String.to_charlist()
    |> :localize_date_time_format_lexer.string()
    |> maybe_add_decimal_separator()
    |> maybe_return_error(format_string)
  end

  def tokenize(%{number_system: _numbers, format: format_string}) do
    tokenize(format_string)
  end

  defp maybe_add_decimal_separator({:ok, token_list, other}) do
    {:ok, seconds_followed_by_fraction(token_list), other}
  end

  defp maybe_add_decimal_separator(other), do: other

  defp seconds_followed_by_fraction([]), do: []

  defp seconds_followed_by_fraction([
         {:second, _, _} = second,
         {:fractional_second, _, _} = fractional_second | rest
       ]) do
    [
      second,
      {:decimal_separator, nil, nil},
      fractional_second
      | seconds_followed_by_fraction(rest)
    ]
  end

  defp seconds_followed_by_fraction([first | rest]) do
    [first | seconds_followed_by_fraction(rest)]
  end

  defp maybe_return_error({:error, {_, :localize_date_time_format_lexer, {_, error}}, _}, format) do
    {:error,
     Localize.DateTimeFormatError.exception(
       format: format,
       reason: :tokenize_error,
       detail: error
     )}
  end

  defp maybe_return_error(other, _format), do: other
end
