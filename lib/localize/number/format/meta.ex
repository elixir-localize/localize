defmodule Localize.Number.Format.Meta do
  @moduledoc """
  Describes the metadata that drives number formatting and
  provides functions to update the struct.

  The metadata is derived from parsing a number format pattern
  (e.g., `"#,##0.###"`) and captures all the information needed
  to format a number: digit counts, grouping, rounding, padding,
  multiplier, and the positive/negative format templates. It is
  returned by `Localize.Number.Format.Compiler.format_to_metadata/1`
  and its type appears in that module's public interface, so it is
  part of the documented API.

  """

  defstruct integer_digits: %{max: 0, min: 1},
            fractional_digits: %{max: 0, min: 0},
            significant_digits: %{max: 0, min: 0},
            exponent_digits: 0,
            exponent_sign: false,
            engineering_grouping: 0,
            scientific_rounding: 0,
            grouping: %{
              fraction: %{first: 0, rest: 0},
              integer: %{first: 0, rest: 0}
            },
            round_nearest: 0,
            padding_length: 0,
            padding_char: " ",
            multiplier: 1,
            currency: nil,
            format: [
              positive: [format: "#"],
              negative: [minus: ~c"-", format: :same_as_positive]
            ],
            number: 0

  @type t :: %__MODULE__{
          currency: nil | map(),
          engineering_grouping: non_neg_integer(),
          exponent_digits: non_neg_integer(),
          exponent_sign: boolean(),
          format: [{:negative, [any(), ...]} | {:positive, [any(), ...]}, ...],
          fractional_digits: %{max: non_neg_integer(), min: non_neg_integer()},
          grouping: %{
            fraction: %{first: non_neg_integer(), rest: non_neg_integer()},
            integer: %{first: non_neg_integer(), rest: non_neg_integer()}
          },
          integer_digits: %{max: non_neg_integer(), min: non_neg_integer()},
          multiplier: non_neg_integer(),
          number: non_neg_integer(),
          padding_char: String.t(),
          padding_length: non_neg_integer(),
          round_nearest: non_neg_integer(),
          scientific_rounding: non_neg_integer(),
          significant_digits: %{max: non_neg_integer(), min: non_neg_integer()}
        }

  @doc """
  Returns a new number formatting metadata struct with default values.

  ### Returns

  * A `Localize.Number.Format.Meta.t()` struct.

  ### Examples

      iex> meta = Localize.Number.Format.Meta.new()
      iex> meta.integer_digits
      %{min: 1, max: 0}
      iex> meta.multiplier
      1

  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc false
  @spec put_integer_digits(t(), non_neg_integer(), non_neg_integer()) :: t()
  def put_integer_digits(%__MODULE__{} = meta, min, max \\ 0)
      when is_integer(min) and is_integer(max) do
    %{meta | integer_digits: %{min: min, max: max}}
  end

  @doc false
  @spec put_fraction_digits(t(), non_neg_integer(), non_neg_integer()) :: t()
  def put_fraction_digits(%__MODULE__{} = meta, min, max \\ 0)
      when is_integer(min) and is_integer(max) do
    %{meta | fractional_digits: %{min: min, max: max}}
  end

  @doc false
  @spec put_significant_digits(t(), non_neg_integer(), non_neg_integer()) :: t()
  def put_significant_digits(%__MODULE__{} = meta, min, max \\ 0)
      when is_integer(min) and is_integer(max) do
    %{meta | significant_digits: %{min: min, max: max}}
  end

  @doc false
  @spec put_exponent_digits(t(), non_neg_integer()) :: t()
  def put_exponent_digits(%__MODULE__{} = meta, digits) when is_integer(digits) do
    %{meta | exponent_digits: digits}
  end

  @doc false
  @spec put_exponent_sign(t(), boolean()) :: t()
  def put_exponent_sign(%__MODULE__{} = meta, flag) when is_boolean(flag) do
    %{meta | exponent_sign: flag}
  end

  @doc false
  # Engineering grouping is the count of mantissa integer digits that the
  # exponent must be a multiple of. Set only for scientific patterns whose
  # mantissa pattern has more allowed integer digits than required, e.g.
  # `##0.###E0` → 3. For pure-scientific (`0.###E0`), fixed-width-mantissa
  # (`00.###E0`), and non-scientific patterns this is 0.
  @spec put_engineering_grouping(t(), non_neg_integer()) :: t()
  def put_engineering_grouping(%__MODULE__{} = meta, group) when is_integer(group) do
    %{meta | engineering_grouping: group}
  end

  @doc false
  @spec put_round_nearest_digits(t(), non_neg_integer()) :: t()
  def put_round_nearest_digits(%__MODULE__{} = meta, digits) when is_integer(digits) do
    %{meta | round_nearest: digits}
  end

  @doc false
  @spec put_scientific_rounding_digits(t(), non_neg_integer()) :: t()
  def put_scientific_rounding_digits(%__MODULE__{} = meta, digits) when is_integer(digits) do
    %{meta | scientific_rounding: digits}
  end

  @doc false
  @spec put_padding_length(t(), non_neg_integer()) :: t()
  def put_padding_length(%__MODULE__{} = meta, digits) when is_integer(digits) do
    %{meta | padding_length: digits}
  end

  @doc false
  @spec put_padding_char(t(), String.t()) :: t()
  def put_padding_char(%__MODULE__{} = meta, char) when is_binary(char) do
    %{meta | padding_char: char}
  end

  @doc false
  @spec put_multiplier(t(), non_neg_integer()) :: t()
  def put_multiplier(%__MODULE__{} = meta, multiplier) when is_integer(multiplier) do
    %{meta | multiplier: multiplier}
  end

  @doc false
  @spec put_integer_grouping(t(), non_neg_integer(), non_neg_integer()) :: t()
  def put_integer_grouping(%__MODULE__{} = meta, first, rest)
      when is_integer(first) and is_integer(rest) do
    grouping = Map.put(meta.grouping, :integer, %{first: first, rest: rest})
    %{meta | grouping: grouping}
  end

  @doc false
  @spec put_integer_grouping(t(), non_neg_integer()) :: t()
  def put_integer_grouping(%__MODULE__{} = meta, all) when is_integer(all) do
    grouping = Map.put(meta.grouping, :integer, %{first: all, rest: all})
    %{meta | grouping: grouping}
  end

  @doc false
  @spec put_fraction_grouping(t(), non_neg_integer(), non_neg_integer()) :: t()
  def put_fraction_grouping(%__MODULE__{} = meta, first, rest)
      when is_integer(first) and is_integer(rest) do
    grouping = Map.put(meta.grouping, :fraction, %{first: first, rest: rest})
    %{meta | grouping: grouping}
  end

  @doc false
  @spec put_fraction_grouping(t(), non_neg_integer()) :: t()
  def put_fraction_grouping(%__MODULE__{} = meta, all) when is_integer(all) do
    grouping = Map.put(meta.grouping, :fraction, %{first: all, rest: all})
    %{meta | grouping: grouping}
  end

  @doc false
  @spec put_format(t(), Keyword.t(), Keyword.t()) :: t()
  def put_format(%__MODULE__{} = meta, positive_format, negative_format) do
    %{meta | format: [positive: positive_format, negative: negative_format]}
  end

  @doc false
  @spec put_format(t(), Keyword.t()) :: t()
  def put_format(%__MODULE__{} = meta, positive_format) do
    put_format(meta, positive_format, minus: ~c"-", format: :same_as_positive)
  end
end
