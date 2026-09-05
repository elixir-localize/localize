defmodule Localize.Unit.Preference do
  @moduledoc """
  Returns the preferred units for a given unit, territory, and usage.

  In many cultures, the common unit of measure for some unit categories
  varies based upon the usage. For example, when describing length in
  the US, the units vary by context:

  * road distance — miles for larger distances, feet for smaller
  * person height — feet and inches
  * snowfall — inches

  This module provides functions to look up CLDR preference data for
  different use cases in different territories.

  """

  alias Localize.Unit
  alias Localize.Unit.{BaseUnit, Conversion, Data, Parser}

  @unit_preferences (
                      geq_to_base = fn unit_name, geq_string ->
                        case geq_string do
                          nil ->
                            0.0

                          "" ->
                            0.0

                          s when is_binary(s) ->
                            case Float.parse(s) do
                              {+0.0, _} ->
                                +0.0

                              {geq_value, _} ->
                                primary = unit_name |> String.split("-and-") |> hd()

                                case Parser.parse(primary) do
                                  {:ok, parsed} ->
                                    case BaseUnit.base_unit(parsed) do
                                      {:ok, base} ->
                                        case Conversion.convert(geq_value, primary, base) do
                                          {:ok, v} -> v
                                          _ -> 0.0
                                        end

                                      _ ->
                                        0.0
                                    end

                                  _ ->
                                    0.0
                                end

                              :error ->
                                0.0
                            end
                        end
                      end

                      Data.unit_preferences()
                      |> Enum.group_by(& &1.category)
                      |> Map.new(fn {category, entries} ->
                        by_usage =
                          entries
                          |> Enum.group_by(& &1.usage)
                          |> Map.new(fn {usage, usage_entries} ->
                            prefs =
                              usage_entries
                              |> Enum.flat_map(fn entry ->
                                Enum.map(entry.preferences, fn p ->
                                  %{
                                    unit: p.unit,
                                    geq: geq_to_base.(p.unit, p[:geq]),
                                    regions: String.split(p.regions, " ", trim: true),
                                    skeleton: p[:skeleton] || ""
                                  }
                                end)
                              end)

                            {usage, prefs}
                          end)

                        {category, by_usage}
                      end)
                    )

  @doc """
  Returns the preferred units for a given unit, territory, and usage.

  The unit's value is converted to the base unit for its category and
  compared against the `geq` (greater-than-or-equal) thresholds in the
  preference data to select the appropriate unit set.

  ### Arguments

  * `unit` is a `t:Localize.Unit.t/0` struct.

  * `options` is a keyword list of options.

  ### Options

  * `:usage` is the unit usage context as an atom (e.g., `:person_height`,
    `:road`). The default is `:default`.

  * `:territory` is a territory code atom (e.g., `:US`, `:GB`). The
    default is derived from the current locale.

  * `:locale` is a locale identifier. Used to derive the territory when
    `:territory` is not provided.

  * `:scope` is `:small` or `nil`. Forward-compatible placeholder for
    CLDR's planned scope-keyed preferences (small-quantity contexts);
    accepted but currently has no effect because no `<unitPreference>`
    in the shipped CLDR data carries a `scope` attribute. Same shape
    as `Cldr.Unit.Preference.preferred_units/3`.

  * `:alt` is `:informal` or `nil`. Forward-compatible placeholder for
    CLDR's planned alt-keyed preferences (informal-context units);
    accepted but currently has no effect because no `<unitPreference>`
    in the shipped CLDR data carries an `alt` attribute.

  ### Returns

  * `{:ok, units, options}` where `units` is a list of unit name atoms
    and `options` is a keyword list of formatting hints (e.g.,
    `[round_nearest: 1]`).

  * `{:error, exception}` if preferences cannot be resolved.

  ### Examples

      iex> meter = Localize.Unit.new!(1, "meter")
      iex> {:ok, units, _opts} = Localize.Unit.Preference.preferred_units(meter, usage: :person, territory: :US)
      iex> units
      [:inch]

      iex> many_meters = Localize.Unit.new!(10_000, "meter")
      iex> {:ok, units, _opts} = Localize.Unit.Preference.preferred_units(many_meters, usage: :road, territory: :US)
      iex> units
      [:mile]

  """
  @spec preferred_units(Unit.t(), Keyword.t()) ::
          {:ok, [atom()], Keyword.t()} | {:error, Exception.t()}
  def preferred_units(%Unit{} = unit, options \\ []) do
    # TR35 orders the sources `mu > ms > rg > (likely) region`, and leaves a
    # unit with no preferences at all in its base units. `-u-ms` and `-u-rg`
    # are folded into the territory, so the three that remain are ordered
    # here: each returns `nil` when it has nothing to say, so the next one
    # is asked.
    measurement_unit_override(options, unit) ||
      locale_preference(unit, options) ||
      base_units(unit)
  end

  defp locale_preference(%Unit{} = unit, options) do
    with category when not is_nil(category) <- unit_category(unit),
         {:ok, base_value} <- base_unit_value(unit),
         {:ok, territory_chain} <-
           Localize.Territory.territory_chain(resolve_territory(options)) do
      usage_chain = build_usage_chain(resolve_usage(options, unit))
      find_preference(category, usage_chain, territory_chain, abs(base_value))
    end
  end

  # The unit expressed in its base units — `kilocandela` is `candela`,
  # `candela-per-cubic-foot` is `candela-per-cubic-meter`.
  defp base_units(%Unit{name: name}) do
    with {:ok, parsed} <- Parser.parse(name),
         {:ok, base} <- BaseUnit.base_unit(parsed) do
      {:ok, [unit_name(base)], []}
    else
      _no_base_unit ->
        {:error,
         Localize.InvalidValueError.exception(
           value: name,
           expected: "a unit with a known category or resolvable base units"
         )}
    end
  end

  # A simple base unit — `candela`, `meter` — has an interned atom, and
  # returning it keeps the shape callers expect. A *compound* base unit is
  # derived from whatever the caller asked for, so the set is unbounded and
  # `String.to_atom/1` would be an atom-table exhaustion vector; those come
  # back as the CLDR identifier string instead.
  defp unit_name(base) do
    base
    |> String.replace("-", "_")
    |> Localize.Utils.Helpers.existing_atom()
    |> Kernel.||(base)
  end

  # Usage may be supplied via the options keyword list (atom or string) or
  # carried on the struct's `:usage` field (set at `Localize.Unit.new/3` time
  # as a CLDR-style hyphenated string, e.g. `"person-height"`). Options win;
  # the struct field is the fallback; `:default` covers the no-info case.
  # Intern an atom for every usage the preference data defines. The data is
  # keyed by usage *string*, so nothing else creates these atoms, and
  # `normalize_usage/1` would then fail `String.to_existing_atom/1` for a
  # perfectly valid usage and silently fall back to `:default` — CLDR's
  # `fluid` usage returned cubic inches for `en-GB` instead of imperial
  # gallons. `String.to_atom/1` is safe here: it runs at compile time over
  # a closed set from CLDR data, never over caller input.
  @known_usages @unit_preferences
                |> Enum.flat_map(fn {_category, by_usage} -> Map.keys(by_usage) end)
                |> Enum.uniq()
                |> Enum.map(&(&1 |> String.replace("-", "_") |> String.to_atom()))
                |> Enum.sort()

  @doc """
  Returns the unit usages CLDR defines preferences for.

  A usage names the context a quantity is being measured in — `:person_height`
  and `:road` are both lengths, but a locale prefers different units for them.

  ### Returns

  * A sorted list of usage atoms.

  ### Examples

      iex> usages = Localize.Unit.Preference.known_usages()
      iex> :fluid in usages
      true

      iex> :person_height in Localize.Unit.Preference.known_usages()
      true

  """
  @spec known_usages() :: [atom(), ...]
  def known_usages, do: @known_usages

  defp resolve_usage(options, %Unit{usage: struct_usage}) do
    case Keyword.get(options, :usage) do
      nil -> normalize_usage(struct_usage) || :default
      explicit -> normalize_usage(explicit) || :default
    end
  end

  defp normalize_usage(nil), do: nil
  defp normalize_usage(usage) when is_atom(usage), do: usage

  # `@known_usages` interns every valid CLDR usage, so an unknown string
  # must not create a new atom — `:usage` may carry user input and
  # unbounded `String.to_atom/1` is an atom-table exhaustion vector.
  # Unknown usages resolve to `nil` and the caller falls back to `:default`
  # per TR35.
  defp normalize_usage(usage) when is_binary(usage) do
    usage
    |> String.replace("-", "_")
    |> Localize.Utils.Helpers.existing_atom()
  end

  @doc """
  Same as `preferred_units/2` but raises on error.

  ### Arguments

  * `unit` is a `t:Localize.Unit.t/0` struct.

  * `options` is a keyword list of options.

  ### Options

  See `preferred_units/2` for the supported options.

  ### Returns

  * A list of unit name atoms.

  ### Examples

      iex> meter = Localize.Unit.new!(1, "meter")
      iex> Localize.Unit.Preference.preferred_units!(meter, usage: :person, territory: :US)
      [:inch]

      iex> many_meters = Localize.Unit.new!(10_000, "meter")
      iex> Localize.Unit.Preference.preferred_units!(many_meters, usage: :road, territory: :US)
      [:mile]

  """
  @spec preferred_units!(Unit.t(), Keyword.t()) :: [atom()] | no_return()
  def preferred_units!(%Unit{} = unit, options \\ []) do
    case preferred_units(unit, options) do
      {:ok, units, _opts} -> units
      {:error, exception} -> raise exception
    end
  end

  # ── Category resolution ─────────────────────────────────────

  # The unit's CLDR quantity, or `nil` when it has none. A unit outside
  # every quantity — `candela-per-byte` — is not an error: it simply has no
  # preferences, and the caller falls back to base units.
  defp unit_category(%Unit{name: name}) do
    with {:ok, parsed} <- Parser.parse(name),
         {:ok, base} <- BaseUnit.base_unit(parsed) do
      btq = Data.base_unit_to_quantity()

      # Try the original unit name first (handles compound units like
      # cubic-meter-per-meter → consumption), then fall back to base unit
      Map.get(btq, name) || Map.get(btq, base)
    else
      _unparseable -> nil
    end
  end

  # ── Base unit value ─────────────────────────────────────────

  defp base_unit_value(%Unit{value: value, name: name}) do
    with {:ok, parsed} <- Parser.parse(name),
         {:ok, base} <- BaseUnit.base_unit(parsed) do
      Conversion.convert(to_float(value), name, base)
    end
  end

  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_number(n), do: n * 1.0
  defp to_float(nil), do: 0.0

  # ── Territory resolution ────────────────────────────────────

  defp resolve_territory(options) do
    case Keyword.get(options, :territory) do
      nil ->
        locale = Keyword.get(options, :locale, Localize.get_locale())

        # TR35 orders the overrides `mu > ms > rg > (likely) region`. `rg`
        # is already folded into the locale's territory, so `ms` is applied
        # over the top of it: a measurement system stands for the
        # preferences of a territory that uses it.
        measurement_system_territory(locale) || territory_from(locale)

      territory ->
        territory
    end
  end

  defp territory_from(locale) do
    case Localize.Territory.territory_from_locale(locale) do
      {:ok, territory} -> territory
      _no_territory -> :US
    end
  end

  # `-u-ms` names a measurement system, and preferences are keyed by
  # territory, so each system is represented by a territory that uses it.
  # `001` is CLDR's own fallback and is metric throughout.
  defp measurement_system_territory(locale) do
    case measurement_system(locale) do
      :metric -> :"001"
      :ussystem -> :US
      :imperial -> :GB
      :uksystem -> :GB
      _none_or_unknown -> nil
    end
  end

  defp measurement_system(locale) do
    with {:ok, %{locale: %{ms: ms}}} when not is_nil(ms) <- Localize.validate_locale(locale) do
      ms
    else
      _no_measurement_system -> nil
    end
  end

  # `-u-mu` overrides the unit itself, above every other preference. CLDR
  # supports it for temperature only, and TR35 says an override that is not
  # convertible from the input unit is ignored — `de-u-mu-celsius` asking
  # for a length still gets centimetres.
  defp measurement_unit_override(options, %Unit{} = unit) do
    with locale when not is_nil(locale) <- Keyword.get(options, :locale),
         {:ok, %{locale: %{mu: mu}}} when not is_nil(mu) <- Localize.validate_locale(locale),
         true <- convertible_from?(unit, mu) do
      {:ok, [mu], []}
    else
      _no_override -> nil
    end
  end

  defp convertible_from?(%Unit{name: name}, target) do
    target_name = target |> Atom.to_string() |> String.replace("_", "-")

    Localize.Unit.Conversion.convertible?(name, target_name)
  end

  # ── Usage chain ─────────────────────────────────────────────

  # Build a chain of usages to try, from most specific to least.
  # For example, :person_height → [:person_height, :person, :default]
  defp build_usage_chain(:default), do: [:default]

  defp build_usage_chain(usage) when is_atom(usage) do
    parts = usage |> Atom.to_string() |> String.split("_")

    chain =
      parts
      |> Enum.scan(fn part, acc -> acc <> "_" <> part end)
      |> Enum.reverse()
      |> Enum.map(&String.to_atom/1)

    chain ++ [:default]
  end

  # ── Preference lookup ───────────────────────────────────────

  # `nil` when no usage in the chain has preferences for this category in
  # any territory in the chain.
  defp find_preference(category, usage_chain, territory_chain, base_value) do
    Enum.find_value(usage_chain, fn usage ->
      find_for_usage(category, usage, territory_chain, base_value)
    end)
  end

  defp find_for_usage(category, usage, territory_chain, base_value) do
    usage_str = Atom.to_string(usage) |> String.replace("_", "-")

    case get_in(@unit_preferences, [category, usage_str]) do
      nil -> nil
      preferences -> find_for_territory(preferences, territory_chain, base_value)
    end
  end

  defp find_for_territory(preferences, territory_chain, base_value) do
    Enum.find_value(territory_chain, fn territory ->
      territory_str = Atom.to_string(territory)
      matching = Enum.filter(preferences, fn p -> territory_str in p.regions end)

      case find_by_geq(matching, base_value) do
        nil -> nil
        result -> result
      end
    end)
  end

  defp find_by_geq([], _value), do: nil

  defp find_by_geq(preferences, base_value) do
    # Process preferences in order. For each:
    # - If geq > 0: check if base_value >= geq (threshold match)
    # - If geq == 0: convert to this unit, check if value >= 1 (size cascade)
    # First match wins. If none match, use the last preference.
    match =
      Enum.find(preferences, fn pref ->
        if pref.geq > 0.0 do
          # Use a small epsilon for floating-point comparison to handle
          # IEEE 754 rounding (e.g., 3.0 feet = 0.9144000000000001 meters)
          base_value >= pref.geq * (1.0 - 1.0e-12)
        else
          # Size cascade: convert base value to this unit, check >= 1
          primary_unit = pref.unit |> String.split("-and-") |> hd()
          converted_value_gte_1?(base_value, primary_unit)
        end
      end)

    case match do
      nil ->
        # Fall back to the last (smallest) preference
        case List.last(preferences) do
          nil -> nil
          pref -> format_result(pref)
        end

      pref ->
        format_result(pref)
    end
  end

  @dialyzer {:nowarn_function, converted_value_gte_1?: 2}
  defp converted_value_gte_1?(base_value, unit_name) do
    with {:ok, parsed} <- Parser.parse(unit_name),
         {:ok, base} <- BaseUnit.base_unit(parsed),
         {:ok, converted} <- Conversion.convert(base_value, base, unit_name) do
      abs(converted) >= 1.0 - 1.0e-8
    else
      _ -> false
    end
  end

  defp format_result(pref) do
    units =
      pref.unit
      |> String.split("-and-")
      |> Enum.map(fn u -> u |> String.replace("-", "_") |> String.to_atom() end)

    skeleton = parse_skeleton(pref)
    {:ok, units, skeleton}
  end

  defp parse_skeleton(%{skeleton: skeleton}) when is_binary(skeleton) and skeleton != "" do
    skeleton
    |> String.split("/")
    |> Enum.flat_map(fn part ->
      case part do
        "1" -> [round_nearest: 1]
        "5" -> [round_nearest: 5]
        "10" -> [round_nearest: 10]
        "50" -> [round_nearest: 50]
        "100" -> [round_nearest: 100]
        _ -> []
      end
    end)
  end

  defp parse_skeleton(_), do: []
end
