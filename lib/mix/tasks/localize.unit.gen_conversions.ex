defmodule Mix.Tasks.Localize.Unit.GenConversions do
  @shortdoc "Generates a dependency-free unit conversion module for embedded targets"

  @moduledoc """
  Generates a self-contained Elixir module that converts units to their
  base units, with no dependency on Localize at all.

  The generated module is intended for targets where compiling Localize
  is too expensive — Nerves devices and other embedded builds, where the
  ~200 modules of the full library cost more compile time than the
  project itself. Localize stays on the developer's machine as the
  generator; the emitted file is committed and compiles in milliseconds.

  Units are selected by *quantity* (`speed`, `temperature`, `length`),
  by *name*, or by both. Selecting a quantity emits every simple unit
  CLDR knows for it plus the compound units CLDR's preference data lists
  for it, which covers a coherent domain rather than a hand-listed set.

  Quantity selection alone does not reach every convertible unit. CLDR's
  preference data lists the compounds people usually *display*, so
  derived units outside that set — `newton-meter`, `kilogram-square-meter`,
  `newton-meter-second-per-radian` — are convertible but not listed under
  any quantity. Name them with `--units`. Anything CLDR can reduce to an
  affine conversion is fair game, compound or not.

  The generated module handles SI prefixes and `-per-` compounds at
  runtime from a prefix table, so `millimeter-per-second` works even
  though it is not itself in the emitted table.

  ### Arguments

  * `--types` is a comma-separated list of CLDR quantities to include,
    for example `speed,temperature`. Run with `--list` to see the
    available quantities.

  * `--units` is a comma-separated list of unit names to include, for
    example `newton-meter,degree-per-second`. Compound units are
    accepted. A name that CLDR does not know, or whose conversion is not
    affine, aborts the task rather than being silently omitted.

  At least one of `--types` and `--units` is required; giving both
  emits the union.

  * `--module` is the name of the module to generate, for example
    `Robot.Units`. The default is `Units`.

  * `--output` is the path to write. The default is derived from the
    module name under `lib/`.

  * `--list` prints the available quantities and exits.

  ### Returns

  * `:ok` after writing the generated file.

  ### Examples

      $ mix localize.unit.gen_conversions --types speed,temperature --module Robot.Units
      * creating lib/robot/units.ex
        speed: 9 units, temperature: 4 units (13 total)

      $ mix localize.unit.gen_conversions \\
          --units newton-meter,kilogram-square-meter,meter-per-square-second \\
          --module Robot.Units
      * creating lib/robot/units.ex
        named: 3 units (3 total)

      $ mix localize.unit.gen_conversions --types temperature --units newton-meter
      * creating lib/units.ex
        temperature: 4 units, named: 1 units (5 total)

      $ mix localize.unit.gen_conversions --list

  """

  use Mix.Task

  alias Localize.Unit.Data

  @switches [types: :string, units: :string, module: :string, output: :string, list: :boolean]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {options, _argv} = OptionParser.parse!(argv, strict: @switches)

    if options[:list] do
      list_quantities()
    else
      generate(options)
    end
  end

  defp list_quantities do
    Mix.shell().info("Available quantities:\n")

    quantities()
    |> Enum.chunk_every(4)
    |> Enum.each(fn row ->
      Mix.shell().info("  " <> Enum.map_join(row, "", &String.pad_trailing(&1, 24)))
    end)
  end

  defp generate(options) do
    types = parse_types!(options)
    names = parse_units(options)

    if types == [] and names == [] do
      Mix.raise("Give --types, --units, or both (see --list)")
    end

    module = options[:module] || "Units"
    output = options[:output] || default_output(module)

    units =
      (Enum.flat_map(types, &units_for_quantity/1) ++ units_for_names(names))
      |> Enum.uniq_by(& &1.name)
      |> Enum.sort_by(& &1.name)

    if units == [] do
      Mix.raise("No convertible units found for #{Enum.join(types, ", ")}")
    end

    contents = render(module, types, names, units)

    File.mkdir_p!(Path.dirname(output))
    File.write!(output, contents)

    Mix.shell().info([:green, "* creating ", :reset, output])
    Mix.shell().info("  " <> summary(types, names, units))
  end

  defp summary(types, names, units) do
    by_quantity =
      Enum.map(types, fn type ->
        "#{type}: #{Enum.count(units, &(&1.quantity == type))} units"
      end)

    by_name = if names == [], do: [], else: ["named: #{length(names)} units"]

    Enum.join(by_quantity ++ by_name, ", ") <> " (#{length(units)} total)"
  end

  defp parse_types!(options) do
    types = split_option(options[:types])
    known = quantities()

    case Enum.reject(types, &(&1 in known)) do
      [] -> types
      unknown -> Mix.raise("Unknown quantities: #{Enum.join(unknown, ", ")} (see --list)")
    end
  end

  defp parse_units(options) do
    split_option(options[:units])
  end

  defp split_option(nil), do: []

  defp split_option(value) do
    value |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
  end

  defp default_output(module) do
    path =
      module
      |> String.split(".")
      |> Enum.map_join("/", &Macro.underscore/1)

    Path.join("lib", path <> ".ex")
  end

  # ── Unit selection ───────────────────────────────────────────────

  defp quantities do
    Data.base_unit_to_quantity() |> Map.values() |> Enum.uniq() |> Enum.sort()
  end

  # Simple units CLDR files under this quantity, plus the compound units
  # its preference data lists for the same quantity. Mixed display units
  # ("foot-and-inch") are formatting constructs, not convertible units,
  # and are dropped.
  defp units_for_quantity(quantity) do
    simple = Map.get(Localize.Unit.known_units_by_category(), quantity, [])

    compound =
      Data.unit_preferences()
      |> Enum.filter(&(&1.category == quantity))
      |> Enum.flat_map(& &1.preferences)
      |> Enum.map(& &1.unit)

    (simple ++ compound)
    |> Enum.uniq()
    |> Enum.reject(&String.contains?(&1, "-and-"))
    |> Enum.flat_map(&describe(&1, quantity))
    |> Enum.sort_by(& &1.name)
  end

  # Units named explicitly. Unlike quantity selection, which sweeps a domain
  # and can reasonably drop a stray unit it cannot tabulate, a name the caller
  # typed is a request: a misspelling or an inconvertible unit is an error,
  # not something to omit silently from the generated table.
  defp units_for_names(names) do
    Enum.map(names, fn name ->
      case describe(name, quantity_for(name)) do
        [unit] ->
          unit

        [] ->
          Mix.raise(
            "Cannot tabulate #{inspect(name)}. Either CLDR does not know it, or its " <>
              "conversion is not affine and cannot be reduced to a factor and offset. " <>
              "Compound units are fine — `newton-meter`, `meter-per-square-second` and " <>
              "`newton-meter-second-per-radian` all resolve."
          )
      end
    end)
  end

  # CLDR assigns a quantity to base units, but several derived base units
  # (`kilogram-square-meter`, `revolution-per-square-meter`) have none, and
  # some classifications surprise — `newton-meter` reduces to the base unit of
  # energy, `degree-per-second` to that of frequency. The quantity is only used
  # for the summary line, so an unclassified unit is reported rather than
  # rejected.
  defp quantity_for(name) do
    case Localize.Unit.BaseUnit.base_unit(name) do
      {:ok, base} -> Map.get(Data.base_unit_to_quantity(), base)
      _error -> nil
    end
  end

  # Points the affine fit is derived from and then checked against. The
  # spread matters: Beaufort is linear over its first few steps and
  # saturates at the top, so a fit validated only near the origin would
  # be accepted and then be badly wrong in the field.
  @fit_points [0, 1, 2, 7.5, 30, 100, 1000]

  # Resolves one unit into the row the template needs. A unit is dropped
  # if it has no conversion at all, or if its conversion is not affine —
  # `base = value * factor + offset` cannot express a piecewise or
  # saturating scale, and emitting one would silently produce wrong
  # numbers rather than fail.
  defp describe(name, quantity) do
    with {:ok, base} <- Localize.Unit.BaseUnit.base_unit(name),
         {:ok, one} <- Localize.Unit.Conversion.convert(1, name, base),
         {:ok, two} <- Localize.Unit.Conversion.convert(2, name, base),
         factor = two - one,
         offset = one - factor,
         :ok <- verify_affine(name, base, factor, offset) do
      [
        %{
          name: name,
          base: base,
          quantity: quantity,
          factor: factor,
          offset: offset,
          aliases: aliases(name)
        }
      ]
    else
      {:error, :not_affine} ->
        Mix.shell().info([
          :yellow,
          "  skipping #{name}: conversion is not affine and cannot be tabulated",
          :reset
        ])

        []

      _error ->
        []
    end
  end

  defp verify_affine(name, base, factor, offset) do
    Enum.reduce_while(@fit_points, :ok, fn value, :ok ->
      if fits?(name, base, factor, offset, value),
        do: {:cont, :ok},
        else: {:halt, {:error, :not_affine}}
    end)
  end

  defp fits?(name, base, factor, offset, value) do
    case Localize.Unit.Conversion.convert(value, name, base) do
      {:ok, expected} ->
        predicted = value * factor + offset
        abs(predicted - expected) <= max(abs(expected) * 1.0e-9, 1.0e-9)

      {:error, _reason} ->
        false
    end
  end

  # Every spelling the generated parser should accept for a unit: the
  # CLDR identifier, its space-separated form, the English long and
  # short forms, and the plural display name. Localize renders a
  # quantity of 1 to obtain the singular, so the leading "1" is stripped.
  defp aliases(name) do
    localized =
      case Localize.Unit.new(1, name) do
        {:ok, unit} ->
          [:long, :short, :narrow]
          |> Enum.flat_map(&rendered(unit, &1))
          |> Enum.concat(display_name(unit))

        {:error, _} ->
          []
      end

    [name, String.replace(name, "-", " ")]
    |> Enum.concat(localized)
    |> Enum.map(&String.downcase(String.trim(&1)))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp rendered(unit, format) do
    case Localize.Unit.to_string(unit, format: format, locale: :en) do
      {:ok, string} -> [strip_leading_one(string)]
      {:error, _} -> []
    end
  end

  defp display_name(unit) do
    case Localize.Unit.display_name(unit, locale: :en) do
      {:ok, name} -> [name]
      {:error, _} -> []
    end
  end

  defp strip_leading_one(string) do
    string
    |> String.replace(~r/^\s*1\s*/u, "")
    |> String.trim()
  end

  # ── Rendering ────────────────────────────────────────────────────

  # The runtime half of the generated module is fixed — only the tables
  # vary — so it is a literal rather than something assembled.
  @runtime_body ~S'''
    @doc """
    Converts a unit literal to its base unit at compile time.

    The sigil resolves during compilation and expands to a literal, so
    no call to this module survives into the emitted code. Only literals
    are accepted — a sigil carrying `\#{...}` interpolation could not be
    resolved at compile time and is a compile error rather than a
    silent fall back to runtime work.

    ### Examples

        iex> import __MODULE__
        iex> ~u"30 kilometers per hour"
        {8.333333333333334, "meter-per-second"}

        iex> ~u"5 km"
        {5000.0, "meter"}

    """
    defmacro sigil_u({:<<>>, _meta, [literal]}, _modifiers) when is_binary(literal) do
      {value, unit} = split_literal!(literal)

      case to_base(value, unit) do
        {:ok, result} ->
          Macro.escape(result)

        {:error, {:unknown_unit, unknown}} ->
          raise ArgumentError, "unknown unit #{inspect(unknown)} in ~u sigil"
      end
    end

    defmacro sigil_u(_ast, _modifiers) do
      raise ArgumentError,
            "the ~u sigil takes a literal with no interpolation so that the " <>
              "conversion resolves at compile time — use to_base/2 for values " <>
              "known only at runtime"
    end

    defp split_literal!(literal) do
      case String.split(String.trim(literal), " ", parts: 2) do
        [value, unit] -> {parse_number!(value), String.trim(unit)}
        _other -> raise ArgumentError, ~s(expected "<value> <unit>", got: #{inspect(literal)})
      end
    end

    defp parse_number!(string) do
      case Float.parse(string) do
        {number, ""} -> number
        _other -> raise ArgumentError, "invalid number #{inspect(string)} in ~u sigil"
      end
    end

    @doc """
    Converts a value in `unit` to its base unit.

    ### Arguments

    * `value` is a number.

    * `unit` is a unit name in any accepted spelling — the CLDR
      identifier (`"kilometer-per-hour"`), a spaced form
      (`"kilometers per hour"`), or the English symbol (`"km/h"`).

    ### Returns

    * `{:ok, {value_in_base_units, base_unit_name}}`, or

    * `{:error, {:unknown_unit, unit}}`.

    ### Examples

        iex> to_base(30, "kilometer-per-hour")
        {:ok, {8.333333333333334, "meter-per-second"}}

        iex> to_base(30, "km/h")
        {:ok, {8.333333333333334, "meter-per-second"}}

    """
    def to_base(value, unit) when is_number(value) and is_binary(unit) do
      with {:ok, {base, factor, offset}} <- resolve(unit) do
        {:ok, {value * factor + offset, base}}
      end
    end

    @doc """
    Resolves a unit name to `{base_unit, factor, offset}`.

    Tries the alias table first, then an SI prefix, then a `-per-`
    compound. Returns `{:error, {:unknown_unit, unit}}` if none apply.

    """
    def resolve(unit) when is_binary(unit) do
      normalized = unit |> String.trim() |> String.downcase()

      with :error <- lookup(normalized),
           :error <- lookup(String.replace(normalized, " ", "-")),
           :error <- prefixed(normalized),
           :error <- compound(normalized) do
        {:error, {:unknown_unit, unit}}
      end
    end

    @doc """
    Returns the canonical CLDR identifiers in the generated table.

    """
    def known_units, do: Map.keys(@units)

    # An exact hit in the table, or a spelling the alias table maps onto
    # one. Aliases are checked second so a canonical name never pays for
    # the indirection.
    defp lookup(unit) do
      case Map.fetch(@units, unit) do
        {:ok, entry} ->
          {:ok, entry}

        :error ->
          with {:ok, canonical} <- Map.fetch(@aliases, unit) do
            Map.fetch(@units, canonical)
          end
      end
    end

    # "millimeter" -> "milli" + "meter". Only scales the factor: an SI
    # prefix on an offset unit is not meaningful and is refused.
    defp prefixed(unit) do
      Enum.find_value(@si_prefixes, :error, fn {prefix, multiplier} ->
        with true <- String.starts_with?(unit, prefix),
             stem = binary_part(unit, byte_size(prefix), byte_size(unit) - byte_size(prefix)),
             {:ok, {base, factor, +0.0}} <- lookup(stem) do
          {:ok, {base, factor * multiplier, 0.0}}
        else
          _other -> nil
        end
      end)
    end

    # "millimeter-per-second" -> numerator / denominator, each resolved
    # in its own right so either side may itself be SI-prefixed. Offset
    # units cannot participate in a compound.
    defp compound(unit) do
      with [numerator, denominator] <- String.split(unit, "-per-", parts: 2),
           {:ok, {base_n, factor_n, +0.0}} <- resolve_part(numerator),
           {:ok, {base_d, factor_d, +0.0}} <- resolve_part(denominator) do
        {:ok, {base_n <> "-per-" <> base_d, factor_n / factor_d, 0.0}}
      else
        _other -> :error
      end
    end

    defp resolve_part(part) do
      with :error <- lookup(part) do
        prefixed(part)
      end
    end
  '''

  # The generated file records how it was produced, so a regeneration after a
  # CLDR update reproduces exactly the same table.
  defp selection_comment(types, names) do
    [
      if(types != [], do: "quantities " <> Enum.join(types, ", ")),
      if(names != [], do: "units " <> Enum.join(names, ", "))
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("; ")
  end

  defp regenerate_flags(types, names) do
    [
      if(types != [], do: "--types " <> Enum.join(types, ",")),
      if(names != [], do: "--units " <> Enum.join(names, ","))
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp render(module, types, names, units) do
    """
    # Generated by `mix localize.unit.gen_conversions`. Do not edit.
    #
    # Selection: #{selection_comment(types, names)}
    # CLDR: #{Localize.version()}
    #
    # Regenerate with:
    #
    #     mix localize.unit.gen_conversions #{regenerate_flags(types, names)} --module #{module}

    defmodule #{module} do
      @moduledoc \"\"\"
      Converts units to their base units. Generated from CLDR data by
      Localize; has no runtime dependencies.

      Conversion is affine — `base = value * factor + offset` — so both
      scaled units (kilometers) and offset units (degrees Celsius) are
      handled. SI prefixes and `-per-` compounds are resolved at call
      time, so units outside the generated table still convert when they
      are built from units that are in it.

      \"\"\"

    #{render_table(units)}

    #{render_aliases(units)}

    #{render_prefixes()}

    #{@runtime_body}
    end
    """
  end

  defp render_table(units) do
    rows =
      Enum.map_join(units, "\n", fn unit ->
        ~s(    #{inspect(unit.name)} => ) <>
          ~s({#{inspect(unit.base)}, #{inspect(unit.factor)}, #{inspect(unit.offset)}},)
      end)

    "  # unit => {base_unit, factor, offset}\n  @units %{\n#{rows}\n  }"
  end

  defp render_aliases(units) do
    rows =
      units
      |> Enum.flat_map(fn unit -> Enum.map(unit.aliases, &{&1, unit.name}) end)
      |> Enum.uniq_by(&elem(&1, 0))
      |> Enum.sort()
      |> Enum.map_join("\n", fn {alias_name, name} ->
        ~s(    #{inspect(alias_name)} => #{inspect(name)},)
      end)

    "  # every accepted spelling => canonical CLDR identifier\n  @aliases %{\n#{rows}\n  }"
  end

  defp render_prefixes do
    rows =
      Data.si_prefix_multipliers()
      |> Enum.sort()
      |> Enum.map_join("\n", fn {prefix, multiplier} ->
        ~s(    #{inspect(prefix)} => #{inspect(multiplier)},)
      end)

    "  @si_prefixes %{\n#{rows}\n  }"
  end
end
