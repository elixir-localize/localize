defmodule Localize.Unit.Conversion.Beaufort do
  @moduledoc """
  Nonlinear conversion between the Beaufort wind force scale and
  meters per second.

  Implements the ICU algorithm using interpolated midpoints between
  the WMO-defined speed thresholds for each Beaufort number.

  Registered as a `:special` custom unit so that the generic
  conversion pipeline dispatches through `forward/1` and `inverse/1`
  rather than using factor-based arithmetic.

  """

  # Minimum m/s threshold for each Beaufort number (0–18).
  # Index 18 is an artificial end value to give a reasonable midpoint for B=17.
  # Source: ICU4C units_converter.cpp minMetersPerSecForBeaufort[].
  @thresholds {0.0, 0.3, 1.6, 3.4, 5.5, 8.0, 10.8, 13.9, 17.2, 20.8, 24.5, 28.5, 32.7, 36.9, 41.4,
               46.1, 51.1, 55.8, 61.4}
  @max_beaufort tuple_size(@thresholds) - 2

  @doc """
  Converts a Beaufort scale value to meters per second.

  Values are clamped to the range [0, 17]. Fractional Beaufort numbers
  are interpolated between adjacent midpoints.

  ### Examples

      iex> Localize.Unit.Conversion.Beaufort.forward(0)
      0.15

      iex> Localize.Unit.Conversion.Beaufort.forward(5)
      9.4

  """
  @spec forward(number()) :: float()
  def forward(beaufort) do
    clamped = min(max(beaufort, 0.0), @max_beaufort * 1.0)
    index = trunc(clamped)
    fraction = clamped - index

    low = elem(@thresholds, index)
    high = elem(@thresholds, index + 1)
    midpoint_low = (low + high) / 2.0

    if fraction == 0.0 do
      midpoint_low
    else
      next_index = min(index + 1, @max_beaufort)
      next_low = elem(@thresholds, next_index)
      next_high = elem(@thresholds, next_index + 1)
      midpoint_high = (next_low + next_high) / 2.0
      midpoint_low + fraction * (midpoint_high - midpoint_low)
    end
  end

  @doc """
  Converts meters per second to a Beaufort scale value.

  Finds the Beaufort band whose midpoint range contains the given
  speed and interpolates within it. Negative speeds return `0.0`.

  ### Examples

      iex> Localize.Unit.Conversion.Beaufort.inverse(9.4)
      5.0

      iex> Localize.Unit.Conversion.Beaufort.inverse(-3)
      0.0

  """
  @spec inverse(number()) :: float()
  def inverse(mps) do
    if mps < 0.0 do
      0.0
    else
      find_band(mps, 0)
    end
  end

  defp find_band(_mps, index) when index >= @max_beaufort do
    @max_beaufort * 1.0
  end

  defp find_band(mps, index) do
    low = elem(@thresholds, index)
    high = elem(@thresholds, index + 1)
    midpoint = (low + high) / 2.0

    next_low = elem(@thresholds, index + 1)
    next_high = elem(@thresholds, min(index + 2, tuple_size(@thresholds) - 1))
    next_midpoint = (next_low + next_high) / 2.0

    if mps < next_midpoint do
      if next_midpoint == midpoint do
        index * 1.0
      else
        index + (mps - midpoint) / (next_midpoint - midpoint)
      end
    else
      find_band(mps, index + 1)
    end
  end
end
