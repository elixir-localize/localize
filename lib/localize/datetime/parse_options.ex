defmodule Localize.DateTime.ParseOptions do
  @moduledoc false

  # Argument checks shared by the public parse functions. They take
  # untrusted input, so anything other than a string with a keyword list
  # of well-formed options returns an error rather than raising.

  @as_values [:struct, :map]

  @doc """
  Validates the input and options passed to a parse function.

  ### Arguments

  * `input` is the value to be parsed.

  * `options` is the options argument passed to the parse function.

  ### Returns

  * `:ok` when `input` is a string and the options are well formed.

  * `{:error, exception}`, a `t:Localize.InvalidValueError.t/0`, otherwise.

  ### Examples

      iex> Localize.DateTime.ParseOptions.validate("May 5, 2026", locale: :en)
      :ok

      iex> {:error, %Localize.InvalidValueError{value: :bogus}} =
      ...>   Localize.DateTime.ParseOptions.validate("May 5, 2026", as: :bogus)

  """
  @spec validate(term(), term()) :: :ok | {:error, Localize.InvalidValueError.t()}
  def validate(input, options) do
    with :ok <- validate_input(input),
         :ok <- validate_options(options),
         :ok <- validate_as(Keyword.get(options, :as, :struct)) do
      validate_reference_date(Keyword.get(options, :reference_date))
    end
  end

  defp validate_input(input) when is_binary(input), do: :ok
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
end
