defmodule Localize.Collation.Unicode do
  @moduledoc false

  # Provides Unicode Character Database lookups for the collation
  # system: canonical combining class and decimal digit detection.
  #
  # Data is loaded from pre-generated ETF files in
  # `priv/localize/supplemental_data/` and cached in
  # `:persistent_term` on first access.

  @combining_classes_key {:localize, :combining_classes}
  @decimal_digit_ranges_key {:localize, :decimal_digit_ranges}

  @doc false
  @spec combining_class(non_neg_integer()) :: non_neg_integer()
  def combining_class(codepoint) do
    classes = load_combining_classes()
    Map.get(classes, codepoint, 0)
  end

  @doc false
  @spec decimal_digit?(non_neg_integer()) :: boolean()
  def decimal_digit?(codepoint) do
    ranges = load_decimal_digit_ranges()
    in_ranges?(codepoint, ranges)
  end

  defp load_combining_classes do
    Localize.DataLoader.load(@combining_classes_key, fn ->
      load_etf("combining_classes.etf")
    end)
  end

  defp load_decimal_digit_ranges do
    Localize.DataLoader.load(@decimal_digit_ranges_key, fn ->
      load_etf("decimal_digit_ranges.etf")
    end)
  end

  defp load_etf(filename) do
    :localize
    |> Application.app_dir(["priv", "localize", "supplemental_data", filename])
    |> File.read!()
    |> :erlang.binary_to_term()
  end

  # Binary search over sorted {start, finish} ranges.
  defp in_ranges?(codepoint, ranges) do
    binary_search(codepoint, ranges, 0, length(ranges) - 1)
  end

  defp binary_search(_cp, _ranges, low, high) when low > high, do: false

  defp binary_search(cp, ranges, low, high) do
    mid = div(low + high, 2)
    {range_start, range_end} = Enum.at(ranges, mid)

    cond do
      cp < range_start -> binary_search(cp, ranges, low, mid - 1)
      cp > range_end -> binary_search(cp, ranges, mid + 1, high)
      true -> true
    end
  end
end
