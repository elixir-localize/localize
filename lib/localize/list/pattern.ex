defmodule Localize.List.Pattern do
  @moduledoc """
  Defines the structure for list formatting patterns.

  Custom patterns of this type may be passed to
  `Localize.List.to_string/2` via the `:list_style` option, so the
  struct is part of the documented API.

  Each pattern has four components used for different list sizes:

  * `:two` — used when the list has exactly two elements.

  * `:start` — used for the first pair of elements in lists
    with three or more elements.

  * `:middle` — used for pairs in the middle of lists with
    four or more elements.

  * `:end` — used for the last pair of elements in lists
    with three or more elements.

  Each component is a pre-parsed token list.

  """

  defstruct [:two, :start, :middle, :end]

  @type token_list :: [String.t() | integer()]

  @type t :: %__MODULE__{
          two: token_list(),
          start: token_list(),
          middle: token_list(),
          end: token_list()
        }

  @doc """
  Creates a new pattern from a map of template strings.

  ### Arguments

  * `options` is a keyword list or map with the keys `:two`,
    `:start`, `:middle`, and `:end`. Each value is either a
    template string like `"{0}, and {1}"` or a pre-parsed
    token list.

  ### Options

  * `:two` is the pattern used when the list has exactly two
    elements. Required.

  * `:start` is the pattern used for the first pair of elements
    in lists with three or more elements. Required.

  * `:middle` is the pattern used for pairs in the middle of
    lists with four or more elements. Required.

  * `:end` is the pattern used for the last pair of elements
    in lists with three or more elements. Required.

  ### Returns

  * `{:ok, pattern}` where pattern is a `t:t/0`.

  * `{:error, reason}` if any required key is missing.

  ### Examples

      iex> Localize.List.Pattern.new(
      ...>   two: "{0} and {1}",
      ...>   start: "{0}, {1}",
      ...>   middle: "{0}, {1}",
      ...>   end: "{0}, and {1}"
      ...> )
      {:ok,
       %Localize.List.Pattern{
         two: [0, " and ", 1],
         start: [0, ", ", 1],
         middle: [0, ", ", 1],
         end: [0, ", and ", 1]
       }}

  """
  @spec new(Keyword.t() | map()) :: {:ok, t()} | {:error, Exception.t()}
  def new(options) when is_list(options) or is_map(options) do
    with {:ok, two} <- parse_field(options, :two),
         {:ok, start} <- parse_field(options, :start),
         {:ok, middle} <- parse_field(options, :middle),
         {:ok, end_pattern} <- parse_field(options, :end) do
      {:ok, %__MODULE__{two: two, start: start, middle: middle, end: end_pattern}}
    end
  end

  @doc """
  Creates a pattern from locale data.

  Locale data uses integer key `2` for the two-element pattern.
  This function normalizes that into the standard struct form.

  ### Arguments

  * `data` is a map from locale data with keys `:start`,
    `:middle`, `:end`, and `2`.

  ### Returns

  * A `t:t/0` struct.

  ### Examples

      iex> Localize.List.Pattern.from_locale_data(%{
      ...>   2 => [0, " and ", 1],
      ...>   start: [0, ", ", 1],
      ...>   middle: [0, ", ", 1],
      ...>   end: [0, ", and ", 1]
      ...> })
      %Localize.List.Pattern{
        two: [0, " and ", 1],
        start: [0, ", ", 1],
        middle: [0, ", ", 1],
        end: [0, ", and ", 1]
      }

  """
  @spec from_locale_data(map()) :: t()
  def from_locale_data(data) when is_map(data) do
    %__MODULE__{
      two: Map.get(data, 2) || Map.get(data, :two),
      start: Map.get(data, :start),
      middle: Map.get(data, :middle),
      end: Map.get(data, :end)
    }
  end

  # ── Private ─────────────────────────────────────────────────

  defp parse_field(options, key) do
    value = access(options, key)

    cond do
      is_nil(value) ->
        {:error,
         Localize.InvalidValueError.exception(
           value: nil,
           expected: "a template string or parsed token list",
           context: "#{key} in Localize.List.Pattern"
         )}

      is_binary(value) ->
        {:ok, Localize.Substitution.parse(value)}

      is_list(value) ->
        {:ok, value}

      true ->
        {:error,
         Localize.InvalidValueError.exception(
           value: value,
           expected: "a template string or parsed token list",
           context: "#{key} in Localize.List.Pattern"
         )}
    end
  end

  defp access(options, key) when is_map(options), do: Map.get(options, key)
  defp access(options, key) when is_list(options), do: Keyword.get(options, key)
end
