defmodule Localize.Collation.Element do
  # A Collation Element (CE) with primary, secondary, and tertiary weights.
  #
  # Elements are represented as `{primary, secondary, tertiary, variable}` tuples
  # for compact persistent_term storage. Constructor and accessor functions provide
  # a readable interface.
  #
  # Weights follow the CLDR/UCA specification:
  #
  # * Primary: base character identity (0x0000-0xFFFF).
  #
  # * Secondary: accent/diacritic differences (0x0000-0x01FF).
  #
  # * Tertiary: case/width/variant differences (0x0000-0x003F).
  #
  @moduledoc false

  @type t :: {non_neg_integer(), non_neg_integer(), non_neg_integer(), boolean()}

  @doc """
  Create a new collation element tuple.

  ### Arguments

  * `primary` - the primary weight (default: `0`).

  * `secondary` - the secondary weight (default: `0`).

  * `tertiary` - the tertiary weight (default: `0`).

  * `variable` - whether this is a variable element (default: `false`).

  ### Returns

  A `{primary, secondary, tertiary, variable}` tuple.

  ### Examples

      iex> Localize.Collation.Element.new(0x23EC, 0x0020, 0x0008, false)
      {0x23EC, 0x0020, 0x0008, false}

  """
  @spec new(non_neg_integer(), non_neg_integer(), non_neg_integer(), boolean()) :: t()
  def new(primary \\ 0, secondary \\ 0, tertiary \\ 0, variable \\ false) do
    {primary, secondary, tertiary, variable}
  end

  @doc """
  Get the primary weight of a collation element.

  ### Arguments

  * `element` - a collation element tuple.

  ### Returns

  The primary weight as a non-negative integer.

  ### Examples

      iex> Localize.Collation.Element.primary({0x23EC, 0x0020, 0x0008, false})
      0x23EC

  """
  @spec primary(t()) :: non_neg_integer()
  def primary({p, _, _, _}), do: p

  @doc """
  Get the secondary weight of a collation element.

  ### Arguments

  * `element` - a collation element tuple.

  ### Returns

  The secondary weight as a non-negative integer.

  ### Examples

      iex> Localize.Collation.Element.secondary({0x23EC, 0x0020, 0x0008, false})
      0x0020

  """
  @spec secondary(t()) :: non_neg_integer()
  def secondary({_, s, _, _}), do: s

  @doc """
  Get the tertiary weight of a collation element.

  ### Arguments

  * `element` - a collation element tuple.

  ### Returns

  The tertiary weight as a non-negative integer.

  ### Examples

      iex> Localize.Collation.Element.tertiary({0x23EC, 0x0020, 0x0008, false})
      0x0008

  """
  @spec tertiary(t()) :: non_neg_integer()
  def tertiary({_, _, t, _}), do: t

  @doc """
  Check if a collation element is completely ignorable.

  A completely ignorable element has all weights (primary, secondary, tertiary)
  set to zero.

  ### Arguments

  * `element` - a collation element tuple.

  ### Returns

  * `true` if all weights are zero.

  * `false` otherwise.

  ### Examples

      iex> Localize.Collation.Element.ignorable?({0, 0, 0, false})
      true

      iex> Localize.Collation.Element.ignorable?({0, 0x0020, 0, false})
      false

  """
  @spec ignorable?(t()) :: boolean()
  def ignorable?({0, 0, 0, _}), do: true
  def ignorable?(_), do: false

  @doc """
  Check if a collation element is primary-ignorable.

  A primary-ignorable element has a primary weight of zero but may have
  non-zero secondary or tertiary weights (e.g., combining accents).

  ### Arguments

  * `element` - a collation element tuple.

  ### Returns

  * `true` if the primary weight is zero.

  * `false` otherwise.

  ### Examples

      iex> Localize.Collation.Element.primary_ignorable?({0, 0x0024, 0x0002, false})
      true

      iex> Localize.Collation.Element.primary_ignorable?({0x23EC, 0x0020, 0x0002, false})
      false

  """
  @spec primary_ignorable?(t()) :: boolean()
  def primary_ignorable?({0, _, _, _}), do: true
  def primary_ignorable?(_), do: false

  @doc """
  Check if a collation element is a variable element.

  Variable elements represent spaces, punctuation, symbols, and currency signs.
  An element is variable when its primary weight falls within the
  `{min, max}` range computed by `Localize.Collation.Variable.primary_range/1`
  for the configured `max_variable` setting. The table's parsed variable
  flag is not consulted — it only reflects the default (punctuation)
  boundary and cannot express the other settings.

  ### Arguments

  * `element` - a collation element tuple.

  * `primary_range` - the `{min, max}` primary weight range for variable elements.

  ### Returns

  * `true` if the element's primary weight lies within the range.

  * `false` otherwise.

  ### Examples

      iex> Localize.Collation.Element.variable?({0x0269, 0x0020, 0x0002, true}, {0x0209, 0x0B61})
      true

      iex> Localize.Collation.Element.variable?({0x23EC, 0x0020, 0x0002, false}, {0x0209, 0x0B61})
      false

  """
  @spec variable?(t(), {pos_integer(), non_neg_integer()}) :: boolean()
  def variable?({p, _, _, _}, {min_primary, max_primary}) do
    p >= min_primary and p <= max_primary
  end
end
