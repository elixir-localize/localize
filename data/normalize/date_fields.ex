defmodule Localize.Data.Normalize.DateFields do
  @moduledoc false

  alias Localize.Data.Normalize.Helpers
  alias Localize.Utils.Map, as: LMap

  def normalize(content, _locale) do
    updated_content = normalize_date_fields(content)
    Map.put(content, "date_fields", updated_content)
  end

  def normalize_date_fields(content) do
    content
    |> get_in(["dates", "fields"])
    |> fold_default_content()
    |> fold_variant_content()
    |> normalize_elements()
    |> LMap.rename_keys("dayperiod", "day_period")
    |> LMap.deep_map(&group_day_period/1, only: "day_period")
    |> LMap.atomize_keys()
  end

  defp group_day_period({key, day_period}) do
    day_period =
      day_period
      |> Enum.map(fn {key, periods} ->
        {key, Helpers.group_by_alt(periods, "display_name")}
      end)
      |> Map.new()

    {key, day_period}
  end

  defp group_day_period(other), do: other

  @base_content_type "standard"

  defp fold_default_content(content) do
    Enum.reduce(base_keys(content), content, fn key, acc ->
      base_content =
        acc
        |> Map.get(key)
        |> normalize_ordinals()

      Map.put(acc, key, %{@base_content_type => base_content})
    end)
  end

  defp fold_variant_content(content) do
    Enum.reduce(variant_keys(content), content, fn key, acc ->
      variant_content =
        acc
        |> Map.get(key)
        |> normalize_ordinals()

      [base_key, variant_key] = base_and_variant_from(key)

      Map.put(acc, base_key, Map.merge(acc[base_key], %{variant_key => variant_content}))
      |> Map.delete(key)
    end)
  end

  @relative_ordinal %{
    "relative_type__2" => -2,
    "relative_type__1" => -1,
    "relative_type_0" => 0,
    "relative_type_1" => 1,
    "relative_type_2" => 2
  }

  @relative_keys Map.keys(@relative_ordinal)

  defp normalize_ordinals(content) do
    relative_ordinals =
      Enum.map(@relative_ordinal, fn {key, ordinal_key} ->
        {ordinal_key, Map.get(content, key)}
      end)
      |> Map.new()

    Map.put(content, "relative_ordinal", relative_ordinals)
    |> Map.drop(@relative_keys)
  end

  defp normalize_elements(content) do
    Enum.map(content, fn {element, data} ->
      {element, normalize_variant(data)}
    end)
    |> Map.new()
  end

  defp normalize_variant(content) do
    Enum.map(content, fn {element, variant} ->
      {element, normalize_relative_times(variant)}
    end)
    |> Map.new()
  end

  defp normalize_relative_times(content) do
    Enum.map(content, fn
      {"relative_time_type_future", relative} ->
        {"relative_future", normalize_time_patterns(relative)}

      {"relative_time_type_past", relative} ->
        {"relative_past", normalize_time_patterns(relative)}

      {"relative_period", relative} ->
        {"relative_period", Localize.Substitution.parse(relative)}

      {key, value} ->
        {key, value}
    end)
    |> Map.new()
  end

  defp normalize_time_patterns(nil), do: %{}

  defp normalize_time_patterns(content) do
    content
    |> Enum.map(fn {"relative_time_pattern_count_" <> type, data} ->
      {type, Localize.Substitution.parse(data)}
    end)
    |> Map.new()
  end

  defp base_keys(content) do
    content
    |> Map.keys()
    |> Enum.reject(&(String.ends_with?(&1, "narrow") or String.ends_with?(&1, "short")))
  end

  defp variant_keys(content) do
    content
    |> Map.keys()
    |> Enum.filter(&(String.ends_with?(&1, "narrow") or String.ends_with?(&1, "short")))
  end

  defp base_and_variant_from(key) do
    parts = String.split(key, "_")
    variant = parts |> Enum.reverse() |> hd()
    base = parts |> Enum.reverse() |> tl() |> Enum.reverse() |> Enum.join("_")
    [base, variant]
  end
end
