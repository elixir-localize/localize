defmodule Localize.Data.Normalize.DateTime do
  @moduledoc false

  alias Localize.Utils.Map, as: LMap
  alias Localize.Data.Normalize.Helpers

  @normalize_number_systems_for [
    "date_formats",
    "time_formats",
    "date_skeletons",
    "time_skeletons"
  ]

  def normalize(content, _locale) do
    dates =
      content
      |> get_in(["dates"])
      |> Map.delete("fields")
      |> LMap.rename_keys("_numbers", "number_system")
      |> LMap.rename_keys("_value", "format")
      |> LMap.rename_keys("_type", "type")
      |> LMap.rename_keys("exemplar_city_alt_formal", "formal")
      |> LMap.rename_keys("date_time_formats_at_time", "date_time_at_formats")
      |> LMap.rename_keys("date_time_formats_relative", "date_time_relative_formats")
      |> LMap.underscore_keys(only: "intervalFormatFallback")
      |> LMap.deep_map(&normalize_number_system/1,
        filter: @normalize_number_systems_for,
        only: "number_system"
      )
      |> LMap.deep_map(&compile_items/1,
        filter: "date_time_formats",
        only: ["interval_format_fallback"]
      )
      |> LMap.deep_map(&compile_items/1,
        filter: "append_items"
      )
      |> LMap.deep_map(&compile_items/1,
        filter: "time_zone_names",
        only: ["gmt_format", "fallback_format"]
      )
      |> LMap.atomize_values(
        filter: "time_zone_names",
        only: ["type"]
      )
      |> LMap.deep_map(&compile_items/1,
        filter: "month_patterns",
        only: "leap"
      )
      |> LMap.deep_map(&group_region_formats/1,
        only: "time_zone_names"
      )
      |> LMap.deep_map(&group_available_formats/1,
        filter: "date_time_formats",
        only: "available_formats"
      )
      |> LMap.deep_map(&group_interval_formats/1,
        filter: "date_time_formats",
        only: "interval_formats"
      )
      |> LMap.deep_map(&group_formats/1,
        only: "time_formats"
      )
      |> LMap.deep_map(&group_formats(&1, :standard),
        only: "date_formats"
      )
      |> LMap.deep_map(&group_day_periods/1,
        filter: "day_periods"
      )
      |> LMap.integerize_keys(filter: "calendars")
      |> LMap.atomize_keys(filter: "calendars", skip: ["number_system", :number_system])
      |> atomize_tz_structural_keys()
      |> LMap.atomize_values(only: [:type])
      |> LMap.atomize_keys(level: 1..2)
      |> add_to_date_time_available_formats(:time_skeletons, :time_formats)
      |> add_to_date_time_available_formats(:date_skeletons, :date_formats)
      |> hoist(:append_items)
      |> hoist(:available_formats)
      |> hoist(:interval_formats)

    Map.put(content, "dates", dates)
  end

  @tz_structural_keys MapSet.new([
                        "zone",
                        "metazone",
                        "region_format",
                        "hour_format",
                        "gmt_format",
                        "gmt_zero_format",
                        "fallback_format",
                        "exemplar_city",
                        "formal",
                        "type",
                        "long",
                        "short",
                        "generic",
                        "standard",
                        "daylight",
                        "number_system"
                      ])

  defp atomize_tz_structural_keys(content) do
    tz = content["time_zone_names"]

    if is_map(tz) do
      atomized =
        tz
        |> deep_atomize_structural()
        |> atomize_tz_data_keys()

      Map.put(content, "time_zone_names", atomized)
    else
      content
    end
  end

  defp deep_atomize_structural(map) when is_map(map) do
    Enum.map(map, fn {k, v} ->
      key =
        if is_binary(k) and MapSet.member?(@tz_structural_keys, k), do: String.to_atom(k), else: k

      {key, deep_atomize_structural(v)}
    end)
    |> Map.new()
  end

  defp deep_atomize_structural(other), do: other

  # Atomize data keys within :zone (two levels: region → city)
  # and :metazone (one level: metazone name).
  defp atomize_tz_data_keys(tz) do
    tz
    |> maybe_update(:zone, &atomize_zone_data_keys/1)
    |> maybe_update(:metazone, &atomize_all_keys/1)
  end

  defp maybe_update(map, key, fun) do
    case Map.get(map, key) do
      nil -> map
      data -> Map.put(map, key, fun.(data))
    end
  end

  defp atomize_zone_data_keys(zone) when is_map(zone) do
    Map.new(zone, fn {region, cities} ->
      atomized_cities =
        if is_map(cities), do: atomize_all_keys(cities), else: cities

      {to_atom(region), atomized_cities}
    end)
  end

  defp atomize_all_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_atom(k), v} end)
  end

  defp to_atom(k) when is_atom(k), do: k
  defp to_atom(k) when is_binary(k), do: String.to_atom(k)

  defp hoist(content, key) do
    calendars =
      Enum.map(content.calendars, fn {calendar, formats} ->
        item = Map.fetch!(formats.date_time_formats, key)
        date_time_formats = Map.delete(formats.date_time_formats, key)

        formats =
          formats
          |> Map.put(:date_time_formats, date_time_formats)
          |> Map.put(key, item)

        {calendar, formats}
      end)
      |> Map.new()

    Map.put(content, :calendars, calendars)
  end

  defp add_to_date_time_available_formats(content, skeletons, standard_formats) do
    calendars =
      Enum.map(content.calendars, fn {calendar, formats} ->
        merged_standard_formats =
          Map.merge(formats[skeletons], formats[standard_formats], fn
            _k, a, b when is_binary(a) ->
              [String.to_atom(a), b]

            _k, %{format: skeleton}, b ->
              [String.to_atom(skeleton), b]
          end)

        new_standard_formats =
          Enum.map(merged_standard_formats, fn {format, [skeleton, _format_string]} ->
            {format, skeleton}
          end)
          |> Map.new()

        added_available_formats =
          merged_standard_formats
          |> Map.values()
          |> Enum.map(&List.to_tuple/1)
          |> Map.new()

        merged_available_formats =
          Map.merge(formats.date_time_formats.available_formats, added_available_formats)

        formats =
          formats
          |> put_in([:date_time_formats, :available_formats], merged_available_formats)
          |> put_in([standard_formats], new_standard_formats)
          |> Map.delete(skeletons)

        {calendar, formats}
      end)
      |> Map.new()

    Map.put(content, :calendars, calendars)
  end

  defp compile_items({key, value}) when is_binary(value) do
    {key, Localize.Substitution.parse(value)}
  end

  defp compile_items(other), do: other

  defp normalize_number_system({"number_system" = key, value}) do
    value =
      value
      |> String.split(";")
      |> Enum.map(&split_number_system/1)
      |> Map.new()
      |> LMap.atomize_values()

    {key, value}
  end

  defp split_number_system(system) do
    case String.split(system, "=") do
      [system] -> {"all", String.trim(system)}
      [format_code, system] -> {String.trim(format_code), String.trim(system)}
    end
  end

  defp group_day_periods({key, periods}) when key in ["narrow", "wide", "abbreviated"] do
    day_periods =
      periods
      |> Helpers.group_by_alt("am")
      |> Helpers.group_by_alt("pm")

    {key, day_periods}
  end

  defp group_day_periods(other), do: other

  defp group_formats(item, default \\ :unicode)

  defp group_formats({key, formats}, default) do
    formats =
      formats
      |> Helpers.group_by_alt("short", default: default)
      |> Helpers.group_by_alt("full", default: default)
      |> Helpers.group_by_alt("medium", default: default)
      |> Helpers.group_by_alt("long", default: default)
      |> Helpers.unnest_if_only_one(["short", "full", "medium", "long"])

    {key, formats}
  end

  defp group_formats(other, _), do: other

  def group_region_formats({"time_zone_names" = key, formats}) do
    {generic, formats} = Map.pop(formats, "region_format")
    {daylight, formats} = Map.pop(formats, "region_format_type_daylight")
    {standard, formats} = Map.pop(formats, "region_format_type_standard")

    region_formats = %{
      generic: Localize.Substitution.parse(generic),
      daylight: Localize.Substitution.parse(daylight),
      standard: Localize.Substitution.parse(standard)
    }

    formats = Map.put(formats, "region_format", region_formats)
    {key, formats}
  end

  defp group_available_formats({"available_formats" = key, formats}) do
    formats =
      formats
      |> Enum.map(fn {name, format} ->
        case String.split(name, "-count-") do
          [_no_count] -> {name, format}
          [name, count] -> {name, %{count => format}}
        end
      end)
      |> Enum.map(fn {name, format} ->
        case String.split(name, "-alt-ascii") do
          [_no_count] -> {name, format}
          [ascii_format, ""] -> {ascii_format, %{ascii: format}}
        end
      end)
      |> Enum.map(fn {name, format} ->
        case String.split(name, "-alt-variant") do
          [_no_count] -> {name, format}
          [variant_format, ""] -> {variant_format, %{variant: format}}
        end
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.map(fn
        {key, [item]} ->
          {key, item}

        {key, [format, %{ascii: ascii_format}]} ->
          {key, %{unicode: format, ascii: ascii_format}}

        {key, [%{ascii: ascii_format}, format]} ->
          {key, %{unicode: format, ascii: ascii_format}}

        {key, [format, %{variant: variant_format}]} ->
          {key, %{default: format, variant: variant_format}}

        {key, [%{variant: variant_format}, format]} ->
          {key, %{default: format, variant: variant_format}}

        {key, list} when is_list(list) ->
          {key, LMap.merge_map_list(list)}
      end)
      |> Map.new()

    {key, formats}
  end

  defp group_interval_formats({"interval_formats" = key, formats}) do
    formats =
      formats
      |> Enum.map(fn {interval_name, interval_formats} ->
        interval_formats = map_interval_formats(interval_formats)
        {interval_name, interval_formats}
      end)
      |> Map.new()

    {key, formats}
  end

  defp map_interval_formats(interval_formats) when is_map(interval_formats) do
    Enum.map(interval_formats, fn
      {name, format} ->
        case String.split(name, "-alt-variant") do
          [_no_count] -> {name, format}
          [variant_format, ""] -> {variant_format, %{variant: format}}
        end
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn
      {key, [item]} ->
        {key, item}

      {key, [format, %{variant: variant_format}]} ->
        {key, %{default: format, variant: variant_format}}

      {key, [%{variant: variant_format}, format]} ->
        {key, %{default: format, variant: variant_format}}

      {key, list} when is_list(list) ->
        {key, LMap.merge_map_list(list)}
    end)
    |> Map.new()
  end

  defp map_interval_formats(interval_formats), do: interval_formats
end
