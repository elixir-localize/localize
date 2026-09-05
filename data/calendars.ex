defmodule Localize.Data.Calendars do
  @moduledoc """
  Generates calendar support data from `calendarData.json`, overlaying the
  curated Japanese era set.

  CLDR 49 ships era data for Meiji onwards only — five of the 237 Japanese
  eras — having dropped everything before it. Localize keeps the full range:
  the use cases that need it (academic publishing, genealogy, museum
  cataloguing, calendar conversion) are the ones CLDR is stepping back from.

  The curated set also corrects what CLDR recorded. A pre-Meiji CLDR entry
  held the *lunisolar* proclamation date in a field the rest of the file
  reads as proleptic Gregorian, so 大化 was `[645, 6, 19]` — 6月19日 of the
  old calendar — where the proleptic Gregorian date is 645-07-20. All 231
  pre-Meiji entries were affected. The conversions, their citations and
  their confidence levels are recorded in
  `plans/japanese_eras_research.json`; the build reads the distilled
  `priv/localize/curated/japanese_eras.json`.

  """

  alias Localize.Utils.Map, as: LMap

  @curated_eras "priv/localize/curated/japanese_eras.json"

  # CLDR's `generic` calendar carries no data Localize consumes.
  @skip_calendars ["generic"]

  @doc """
  Generates calendar support data.

  Returns a map of calendar name atoms to maps with `:calendar_system`,
  `:eras` and `:inherit_eras` keys. Each era is `[index, attributes]` where
  the attributes carry `:start` and/or `:end` as `[year, month, day]`, and
  `:code` and `:aliases` where CLDR names them.

  ### Returns

  * A map of `%{atom() => map()}`.

  """
  @spec generate_calendars() :: %{atom() => map()}
  def generate_calendars do
    Localize.Data.read_json("calendarData.json")
    |> get_in(["supplemental", "calendarData"])
    |> Enum.reject(fn {calendar, _data} -> calendar in @skip_calendars end)
    |> Map.new(fn {calendar, data} -> {calendar_key(calendar), calendar_data(calendar, data)} end)
  end

  @doc """
  Returns the curated Japanese eras as `[index, attributes]` entries.

  ### Returns

  * A list of `[non_neg_integer(), map()]` entries ordered by index.

  """
  @spec curated_japanese_eras() :: [[non_neg_integer() | map()]]
  def curated_japanese_eras do
    @curated_eras
    |> File.read!()
    |> :json.decode()
    |> Map.fetch!("eras")
    |> Enum.sort_by(&Map.fetch!(&1, "idx"))
    |> Enum.map(&curated_era/1)
  end

  defp curated_era(%{"idx" => index, "start" => start} = era) do
    attributes = %{start: date_triple(start)}

    attributes =
      case Map.get(era, "code") do
        code when is_binary(code) -> Map.put(attributes, :code, String.to_atom(code))
        _no_code -> attributes
      end

    # 白鳳 is a 私年号 — a folk era never proclaimed by the imperial court —
    # so it is flagged rather than silently mixed in with the official ones.
    attributes =
      if Map.get(era, "private_era"),
        do: Map.put(attributes, :private_era, true),
        else: attributes

    # Four entries have no primary-source attestation yet. They are still
    # published — dropping them would break the index space consumers hold —
    # but flagged so a caller that needs attested data can filter them.
    attributes =
      if Map.get(era, "status") == "needs_research",
        do: Map.put(attributes, :unverified, true),
        else: attributes

    [index, attributes]
  end

  defp calendar_data("japanese", data) do
    data
    |> base_calendar_data()
    |> Map.put(:eras, curated_japanese_eras())
  end

  defp calendar_data(_calendar, data), do: base_calendar_data(data)

  defp base_calendar_data(data) do
    Enum.reduce(data, %{}, fn
      {"calendarSystem", system}, acc ->
        Map.put(acc, :calendar_system, String.to_atom(system))

      {"inheritEras", %{"_calendar" => calendar}}, acc ->
        Map.put(acc, :inherit_eras, %{calendar: String.to_atom(calendar)})

      {"eras", eras}, acc ->
        Map.put(acc, :eras, cldr_eras(eras))

      {_other_key, _value}, acc ->
        acc
    end)
  end

  defp cldr_eras(eras) do
    eras
    |> Enum.map(fn {index, attributes} ->
      [String.to_integer(index), era_attributes(attributes)]
    end)
    |> Enum.sort_by(&hd/1)
  end

  defp era_attributes(attributes) do
    Map.new(attributes, fn {key, value} ->
      key = key |> String.trim_leading("_") |> LMap.underscore() |> String.to_atom()

      case key do
        :start -> {key, date_triple(value)}
        :end -> {key, date_triple(value)}
        :code -> {key, String.to_atom(value)}
        # CLDR writes aliases as a space-separated string.
        :aliases -> {key, String.split(value, " ", trim: true)}
        _other -> {key, value}
      end
    end)
  end

  # CLDR writes an era boundary as `Y-MM-DD`, with a negative year for the
  # proleptic dates the Chinese and Hebrew calendars start from.
  defp date_triple("-" <> rest) do
    [year, month, day] = date_triple(rest)
    [-year, month, day]
  end

  defp date_triple(date) do
    date
    |> String.split("-")
    |> Enum.map(&String.to_integer/1)
  end

  defp calendar_key(calendar) do
    calendar |> String.replace("-", "_") |> String.to_atom()
  end
end
