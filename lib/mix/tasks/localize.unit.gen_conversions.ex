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

  The generated module accepts every unit `Localize.Unit` accepts, so
  there is nothing to select and no arguments to give. That covers the
  155 units CLDR defines a conversion for, every SI-prefixed form of
  them, every power (`square-`, `cubic-`, `pow4-`), and every compound
  built with `-per-` or by juxtaposition — `newton-meter`,
  `kilogram-square-meter`, `newton-meter-second-per-radian`,
  `millitherm-us-per-square-second`. The accepted set is unbounded, so it
  is not tabulated: identifiers are parsed and reduced to a canonical
  base unit at call time.

  Parity with `Localize.Unit` is structural rather than maintained.
  Localize's own unit parser is written as a NimbleParsec template, and
  `mix nimble_parsec.compile` expands it into plain Elixir functions with
  no runtime dependency. That expansion is inlined into the generated
  file, so the emitted module parses identifiers with the same code
  Localize does — there is no second grammar to keep in step.

  Base units are canonical: `resolve/1` returns the same base identifier
  `Localize.Unit.BaseUnit.base_unit/1` returns, with the same factor.

  ### Arguments

  * `--module` is the name of the module to generate, for example
    `Robot.Units`. The default is `Units`.

  * `--output` is the path to write. The default is derived from the
    module name under `lib/`.

  ### Returns

  * `:ok` after writing the generated file.

  ### Examples

      $ mix localize.unit.gen_conversions
      * creating lib/units.ex
        155 units, 655 spellings, every prefixed and compound form of them

      $ mix localize.unit.gen_conversions --module Robot.Units
      * creating lib/robot/units.ex

      $ mix localize.unit.gen_conversions --module Robot.Units --output lib/units.ex

  """

  use Mix.Task

  alias Localize.Unit.Data

  @switches [module: :string, output: :string]

  # Earlier versions emitted a table of selected units, so the caller had to say
  # which ones. The generated module now accepts everything, and a caller who
  # still passes a selection deserves to be told why it is gone rather than
  # given `OptionParser`'s bare "unknown option".
  @retired_switches ~w(--types --units --list)

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")

    case Enum.filter(@retired_switches, &(&1 in argv)) do
      [] -> :ok
      retired -> Mix.raise(retirement_message(retired))
    end

    {options, _argv} = OptionParser.parse!(argv, strict: @switches)

    generate(options)
  end

  defp retirement_message(retired) do
    "#{Enum.join(retired, " and ")} #{if length(retired) == 1, do: "is", else: "are"} no longer " <>
      "needed. The generated module accepts every unit Localize.Unit accepts — defined, " <>
      "prefixed, powered and compound — so there is nothing to select. Run the task with no " <>
      "arguments, or with --module to name the module."
  end

  defp generate(options) do
    module = options[:module] || "Units"
    output = options[:output] || default_output(module)
    aliases = alias_table()

    contents = render(module, aliases)

    File.mkdir_p!(Path.dirname(output))
    File.write!(output, contents)

    Mix.shell().info([:green, "* creating ", :reset, output])

    Mix.shell().info(
      "  #{map_size(Map.new(Data.conversions()))} units, #{map_size(aliases)} spellings, " <>
        "every prefixed and compound form of them"
    )
  end

  defp default_output(module) do
    path =
      module
      |> String.split(".")
      |> Enum.map_join("/", &Macro.underscore/1)

    Path.join("lib", path <> ".ex")
  end

  # ── Parser generation ────────────────────────────────────────────

  # The emitted module must accept every identifier Localize accepts. Rather
  # than maintain a second parser, Localize's own is inlined: it is already
  # written as a NimbleParsec template (the `# parsec:` markers), and
  # `mix nimble_parsec.compile` expands it into plain functions with no
  # runtime dependency. Parity is therefore structural, not maintained.
  #
  # The helpers keep their own module, as they do in Localize. Folding them
  # into the parser would let the compiler see that a post-traverse callback
  # never returns a two-element tuple and warn about the clauses NimbleParsec
  # generates for one — warnings in a file the caller is expected to commit
  # and compile with `--warnings-as-errors`.
  #
  # Sources are located through `module_info/1` rather than a path, so this
  # works whether Localize is the current project or a dependency.
  defp parser_source(module) do
    parser_module = module <> ".Parser"

    helpers_module(parser_module) <> "\n" <> compiled_parser(parser_module)
  end

  defp compiled_parser(parser_module) do
    # `nimble_parsec.compile` has to evaluate the template to expand the
    # combinators, which defines the template's module in this VM. Naming it
    # after the caller's module would leave a namesake behind carrying
    # different code, so it is built under a scratch name and renamed in the
    # text afterwards.
    scratch = "Localize.Unit.GenConversions.Scratch.Parser"

    template =
      Localize.Unit.Parser
      |> source_path()
      |> File.read!()
      |> String.replace("defmodule Localize.Unit.Parser do", "defmodule #{scratch} do")
      |> String.replace("# parsec:Localize.Unit.Parser", "# parsec:#{scratch}")

    directory =
      Path.join(
        System.tmp_dir!(),
        "localize_gen_conversions_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)
    shell = Mix.shell()

    try do
      File.write!(Path.join(directory, "parser.ex.exs"), template)

      # `nimble_parsec.compile` narrates the file it writes, which is a
      # temporary path the caller has no interest in. The caller's own shell is
      # put back afterwards rather than assumed to be the default one.
      Mix.shell(Mix.Shell.Quiet)
      Mix.Task.rerun("nimble_parsec.compile", [Path.join(directory, "parser.ex.exs")])

      directory
      |> Path.join("parser.ex")
      |> File.read!()
      |> String.replace(scratch, parser_module)
      |> strip_generator_banner()
      |> localize_free(parser_module)
      |> quiet_generated_warnings()
    after
      Mix.shell(shell)
      File.rm_rf!(directory)
    end
  end

  defp source_path(module) do
    module.module_info(:compile)[:source] |> to_string()
  end

  # `nimble_parsec.compile` stamps the source path and the time of the run into
  # the file it writes. Both are noise here — the path is a temporary directory
  # that no longer exists, and a timestamp would make two runs of this task on
  # the same CLDR data produce different files, which the header promises they
  # do not.
  defp strip_generator_banner(source) do
    String.replace(source, ~r/^# Generated (from|at) .*\n/m, "")
  end

  # Everything the parser reaches for outside itself. `parse/1` builds a
  # `Localize.ParseError` on failure, which the generated module has no use for
  # — it discards the reason and reports `{:unknown_unit, _}` — so the
  # constructor becomes a plain tagged tuple. Custom units are registered at
  # runtime against Localize; a generated module has no registry, so no name
  # can be one. The byte cap is inlined at its default, there being no
  # `:localize` application to configure it through.
  defp localize_free(source, parser_module) do
    source
    |> String.replace(
      "  import Localize.Unit.Parser.Helpers\n",
      "  import #{parser_module}.Helpers\n"
    )
    |> String.replace("Localize.ParseError.exception(", "parse_error(")
    # The constructor above no longer returns an exception, so the spec
    # written for Localize's parser is false here. Left uncorrected,
    # dialyzer takes `Exception.t()` at its word, decides the error branch
    # cannot produce what the callers match on, and reports an unreachable
    # clause in `parse_identifier/1` — in a file the caller is told to
    # commit and may compile with `--warnings-as-errors`.
    |> String.replace(
      "@spec parse(String.t()) :: {:ok, tuple()} | {:error, Exception.t()}",
      "@spec parse(String.t()) :: {:ok, tuple()} | {:error, {:parse_error, keyword()}}"
    )
    |> String.replace("Localize.Unit.CustomRegistry.registered?(", "custom_unit?(")
    |> String.replace(
      "Application.get_env(:localize, :max_unit_bytes, @default_max_unit_bytes)",
      "@default_max_unit_bytes"
    )
    |> strip_docs()
    |> append_to_module("""
        defp parse_error(bindings), do: {:parse_error, bindings}
    """)
  end

  # The parser's documentation is written about `Localize.Unit.Parser` — its
  # name appears in every doctest — and the generated module is not it. The
  # module is internal, so the docs go rather than being rewritten.
  defp strip_docs(source) do
    source
    |> String.replace(~r/^[ \t]*@(module)?doc[ \t]+"""\n.*?^[ \t]*"""\n/ms, "")
    |> String.replace(~r/^[ \t]*@(module)?doc[ \t]+(false|"[^\n]*")\n/m, "")
  end

  # NimbleParsec generates code for the general case, so parts of it are
  # unreachable for this particular grammar: entry points for sub-combinators
  # nothing calls, an error binding nothing reads, and a compatibility clause
  # for a post-traverse return shape none of these callbacks use. None is a
  # defect. Compiled from AST, as NimbleParsec normally is, all three are
  # marked generated and the compiler stays quiet; written out as source that
  # marking is lost and they warn — in a file the caller commits.
  defp quiet_generated_warnings(source) do
    source
    |> String.replace(
      ~r/\n[ \t]*\{acc, context\} ->\n[ \t]*IO\.warn\(.*?\)\n\n[ \t]*\{rest, acc, context\}\n/s,
      "\n"
    )
    # Drop the binding only where the clause body does not go on to return it;
    # the lookahead is what tells those two shapes apart.
    |> String.replace(~r/\} = error ->\n(?![ \t]*error\n)/, "} ->\n")
    |> String.replace(
      ~r/^  defp (\w+)\(binary, opts \\\\ \[\]\) when is_binary\(binary\) do$/m,
      "  @doc false\n  def \\1(binary, opts \\\\\\\\ []) when is_binary(binary) do"
    )
  end

  # The helpers Localize's parser imports, lifted into the generated file. Only
  # the SI prefix lookup reaches outside the module; it is replaced by a table.
  defp helpers_module(parser_module) do
    body =
      Localize.Unit.Parser.Helpers
      |> source_path()
      |> File.read!()
      |> body_of_module()
      |> strip_docs()
      |> String.replace("Localize.Unit.Data.si_prefix_atom(value)", "si_prefix_atom(value)")

    """
    defmodule #{parser_module}.Helpers do
      @moduledoc false

      # Runtime helpers called by the pre-compiled parser, and the post-traverse
      # callbacks its grammar refers to by name.
    #{body}
      @si_prefix_atoms %{#{si_prefix_atom_pairs()}}

      defp si_prefix_atom(name), do: Map.get(@si_prefix_atoms, name)

      @reserved_categories MapSet.new(#{inspect(Data.categories())})

      def reject_categories(rest, [name] = args, context, _line, _offset) do
        if MapSet.member?(@reserved_categories, name) do
          {:error, "\#{name} is a reserved category name"}
        else
          {rest, args, context}
        end
      end

      # Custom units are registered at runtime against Localize, and a generated
      # module has no registry, so this set is permanently empty. It stays a set
      # rather than becoming a literal `false` because the compiler would then
      # see every branch guarding on it as unreachable and warn — in a file the
      # caller is expected to commit and compile with `--warnings-as-errors`.
      @custom_units MapSet.new()

      def custom_unit?(name), do: MapSet.member?(@custom_units, name)

      def validate_prefixed_custom_unit(rest, args, context, _line, _offset) do
        case List.keyfind(args, :base, 0) do
          {:base, base} when base != nil ->
            if custom_unit?(base) do
              {rest, args, context}
            else
              {:error, "\#{base} is not a registered custom unit"}
            end

          _other ->
            {:error, "no base unit found"}
        end
      end
    end
    """
  end

  # Insert before a module's final `end`. `:binary.matches/2` reports byte
  # offsets and the source is not ASCII, so the cut must be a binary operation —
  # `String.slice/3` counts graphemes and would land past that `end`.
  defp append_to_module(source, addition) do
    index = source |> String.trim_trailing() |> :binary.matches("\nend") |> List.last() |> elem(0)

    binary_part(source, 0, index) <> "\n" <> addition <> "end\n"
  end

  defp si_prefix_atom_pairs do
    Data.si_prefix_names()
    |> Enum.map_join(", ", fn name ->
      "#{inspect(name)} => #{inspect(Data.si_prefix_atom(name))}"
    end)
  end

  defp body_of_module(source) do
    source
    |> String.split("\n")
    |> Enum.drop_while(&(not String.starts_with?(&1, "defmodule")))
    |> Enum.drop(1)
    |> Enum.reverse()
    |> Enum.drop_while(&(String.trim(&1) != "end"))
    |> Enum.drop(1)
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  # ── Spellings ────────────────────────────────────────────────────

  # The parser reads CLDR identifiers, but people write "km/h" and
  # "kilometers per hour". Those spellings are mapped onto the identifier
  # before parsing, which is the one thing the generated module cannot derive
  # from the parser alone.
  #
  # The set covered is every unit CLDR gives a display form for: the 155 it
  # defines a conversion for, plus the compounds its preference data lists.
  # Compounds outside that set — `newton-meter-second-per-radian` — still
  # convert, but only under their CLDR identifier, because CLDR gives no
  # symbol or plural for them to be spelled with.
  defp alias_table do
    spelled_units()
    |> Enum.flat_map(fn name -> Enum.map(aliases(name), &{&1, name}) end)
    |> Enum.reduce(%{}, fn {spelling, name}, acc ->
      # First writer wins: a spelling shared by two units keeps the one that
      # sorts first, so the table does not depend on traversal order.
      Map.put_new(acc, spelling, name)
    end)
  end

  defp spelled_units do
    compound =
      Data.unit_preferences()
      |> Enum.flat_map(& &1.preferences)
      |> Enum.map(& &1.unit)

    simple = Localize.Unit.known_units_by_category() |> Map.values() |> List.flatten()

    # "foot-and-inch" is a formatting construct, not a convertible unit.
    (simple ++ compound)
    |> Enum.uniq()
    |> Enum.reject(&String.contains?(&1, "-and-"))
    |> Enum.sort()
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

    Any spelling in the alias table is mapped onto its CLDR identifier
    first; the identifier is then parsed and reduced. Returns
    `{:error, {:unknown_unit, unit}}` for anything that does not resolve.

    """
    def resolve(unit) when is_binary(unit) do
      normalized = unit |> String.trim() |> String.downcase()

      case resolve_identifier(canonical(normalized)) do
        {:ok, _resolved} = ok -> ok
        {:error, _reason} -> {:error, {:unknown_unit, unit}}
      end
    end

    @doc """
    Returns the CLDR identifiers of the units in the generated tables.

    This is a floor rather than the full accepted set: every SI-prefixed,
    powered and `-per-` compound form built from these also converts, and
    that set is unbounded.

    """
    def known_units, do: Map.keys(@conversions) ++ @simple_base_units

    defp canonical(normalized) do
      case Map.fetch(@aliases, normalized) do
        {:ok, identifier} -> identifier
        :error -> Map.get(@aliases, String.replace(normalized, " ", "-"), normalized)
      end
    end

    # ── Resolution ────────────────────────────────────────────────
    #
    # Identifiers are parsed by the inlined Localize parser, so anything
    # Localize accepts is accepted here: prefixes, powers, multi-unit
    # numerators and denominators, and arbitrary `-per-` compounds. The
    # parsed form is then reduced to a canonical base unit and an affine
    # factor, exactly as Localize does.

    defp resolve_identifier(identifier) do
      with {:ok, ast} <- parse_identifier(identifier),
           {:ok, powers} <- decompose(ast),
           {:ok, factor, offset} <- scale(ast) do
        {:ok, {recompose(powers), factor, offset}}
      end
    end

    defp parse_identifier(identifier) do
      case __MODULE__.Parser.parse(identifier) do
        {:ok, ast} -> {:ok, ast}
        _other -> {:error, {:unknown_unit, identifier}}
      end
    end

    # ── Base unit derivation ──────────────────────────────────────

    defp decompose({:unit, keyword}) do
      with {:ok, numerator} <- decompose_list(Keyword.get(keyword, :numerator, [])),
           {:ok, denominator} <- decompose_list(Keyword.get(keyword, :denominator, [])) do
        {:ok, merge_powers(numerator, Map.new(denominator, fn {u, p} -> {u, -p} end))}
      end
    end

    defp decompose({:single_unit, _} = single), do: decompose_single(single)

    # A mixed unit ("foot-and-inch") is a way of displaying one quantity, not a
    # unit with a conversion — one foot-and-inch is not a length. Localize
    # refuses to convert them too.
    defp decompose(_other), do: {:error, :unsupported_unit}

    defp decompose_list(units) do
      Enum.reduce_while(units, {:ok, %{}}, fn unit, {:ok, acc} ->
        case decompose_single(unit) do
          {:ok, powers} -> {:cont, {:ok, merge_powers(acc, powers)}}
          error -> {:halt, error}
        end
      end)
    end

    defp decompose_single({:single_unit, keyword}) do
      base = Keyword.fetch!(keyword, :base)
      power = Keyword.get(keyword, :power)

      case Map.fetch(@conversions, base) do
        {:ok, base_string} ->
          {:ok, apply_power(parse_base_string(base_string), power)}

        :error ->
          if base in @simple_base_units do
            {:ok, apply_power(%{base => 1}, power)}
          else
            {:error, {:unknown_unit, base}}
          end
      end
    end

    defp decompose_single({:constant, _value}), do: {:ok, %{}}
    defp decompose_single(_other), do: {:error, :unsupported_unit}

    defp parse_base_string("per-" <> denominator), do: product(denominator, -1)

    defp parse_base_string(string) do
      case String.split(string, "-per-", parts: 2) do
        [numerator] -> product(numerator, 1)
        [numerator, denominator] -> merge_powers(product(numerator, 1), product(denominator, -1))
      end
    end

    defp product("", _sign), do: %{}
    defp product(string, sign), do: product_tokens(string, sign, %{})

    defp product_tokens("", _sign, acc), do: acc

    defp product_tokens(string, sign, acc) do
      {multiplier, rest} = consume_power_prefix(string)
      {name, remainder} = consume_simple_unit(rest)
      acc = Map.update(acc, name, sign * multiplier, &(&1 + sign * multiplier))

      case remainder do
        "" -> acc
        "-" <> tail -> product_tokens(tail, sign, acc)
        _other -> acc
      end
    end

    defp consume_power_prefix("square-" <> rest), do: {2, rest}
    defp consume_power_prefix("cubic-" <> rest), do: {3, rest}

    defp consume_power_prefix("pow" <> rest = string) do
      case Integer.parse(rest) do
        {n, "-" <> tail} -> {n, tail}
        _other -> {1, string}
      end
    end

    defp consume_power_prefix(string), do: {1, string}

    # Base unit names may themselves contain hyphens, so the longest match
    # wins — @simple_base_units is emitted longest-first for that reason.
    defp consume_simple_unit(string) do
      case Enum.find(@simple_base_units_by_length, &String.starts_with?(string, &1)) do
        nil ->
          case String.split(string, "-", parts: 2) do
            [token, rest] -> {token, "-" <> rest}
            [token] -> {token, ""}
          end

        unit ->
          {unit, String.slice(string, String.length(unit)..-1//1)}
      end
    end

    defp apply_power(powers, nil), do: powers
    defp apply_power(powers, :square), do: Map.new(powers, fn {u, p} -> {u, p * 2} end)
    defp apply_power(powers, :cubic), do: Map.new(powers, fn {u, p} -> {u, p * 3} end)
    defp apply_power(powers, {:pow, n}), do: Map.new(powers, fn {u, p} -> {u, p * n} end)

    defp merge_powers(left, right) do
      left
      |> Map.merge(right, fn _unit, a, b -> a + b end)
      |> Enum.reject(fn {_unit, power} -> power == 0 end)
      |> Map.new()
    end

    defp recompose(powers) when powers == %{}, do: ""

    defp recompose(powers) do
      {numerator, denominator} =
        powers
        |> Enum.reject(fn {_unit, power} -> power == 0 end)
        |> Enum.split_with(fn {_unit, power} -> power > 0 end)

      numerator_string = numerator |> sort_canonically() |> format_product()

      denominator_string =
        denominator
        |> Enum.map(fn {unit, power} -> {unit, abs(power)} end)
        |> sort_canonically()
        |> format_product()

      case {numerator_string, denominator_string} do
        {"", ""} -> ""
        {n, ""} -> n
        {"", d} -> "per-" <> d
        {n, d} -> n <> "-per-" <> d
      end
    end

    defp sort_canonically(units) do
      Enum.sort_by(units, fn {unit, _power} -> Map.get(@simple_unit_order, unit, 999) end)
    end

    defp format_product([]), do: ""

    defp format_product(units) do
      Enum.map_join(units, "-", fn {unit, power} -> powered_unit(unit, power) end)
    end

    defp powered_unit(unit, 1), do: unit
    defp powered_unit(unit, 2), do: "square-" <> unit
    defp powered_unit(unit, 3), do: "cubic-" <> unit
    defp powered_unit(unit, n), do: "pow" <> Integer.to_string(n) <> "-" <> unit

    # ── Factor composition ────────────────────────────────────────

    defp scale({:unit, keyword}) do
      numerator = Keyword.get(keyword, :numerator, [])
      denominator = Keyword.get(keyword, :denominator, [])

      with {:ok, factor_n, offset_n} <- scale_list(numerator),
           {:ok, factor_d, _offset_d} <- scale_list(denominator) do
        {:ok, factor_n / factor_d, offset(offset_n, numerator, denominator)}
      end
    end

    defp scale(_other), do: {:error, :unsupported_unit}

    # An offset only means something for a unit standing on its own.
    # "celsius" is an affine temperature; "kilocelsius" and "celsius-per-hour"
    # are scales built from one, and carry no zero point. A power keeps it —
    # "square-celsius" converts like "celsius" — which is how CLDR reads them.
    defp offset(offset, [{:single_unit, keyword}], []) do
      if Keyword.get(keyword, :prefix), do: 0.0, else: offset
    end

    defp offset(_offset, _numerator, _denominator), do: 0.0

    defp scale_list(units) do
      Enum.reduce_while(units, {:ok, 1.0, 0.0}, fn unit, {:ok, factor, offset} ->
        case scale_single(unit) do
          {:ok, f, o} -> {:cont, {:ok, factor * f, if(o != 0.0, do: o, else: offset)}}
          error -> {:halt, error}
        end
      end)
    end

    defp scale_single({:single_unit, keyword}) do
      base = Keyword.fetch!(keyword, :base)
      multiplier = prefix_multiplier(Keyword.get(keyword, :prefix))
      exponent = power_exponent(Keyword.get(keyword, :power))

      case Map.fetch(@factors, base) do
        # CLDR marks a non-affine scale (beaufort) as :special. It cannot be
        # reduced to a factor and offset, so it is refused rather than guessed.
        {:ok, {factor, _offset}} when not is_number(factor) ->
          {:error, {:not_affine, base}}

        {:ok, {factor, offset}} ->
          {:ok, :math.pow(factor * multiplier, exponent), offset}

        :error ->
          if base in @simple_base_units do
            {:ok, :math.pow(multiplier, exponent), 0.0}
          else
            {:error, {:unknown_unit, base}}
          end
      end
    end

    defp scale_single({:constant, value}) when is_number(value), do: {:ok, value * 1.0, 0.0}

    defp scale_single({:constant, value}) when is_binary(value) do
      case Float.parse(value) do
        {number, ""} -> {:ok, number, 0.0}
        _other -> {:error, {:unsupported_constant, value}}
      end
    end

    defp scale_single(_other), do: {:error, :unsupported_unit}

    # The parser tags prefixes as atoms; the multiplier table is keyed the same
    # way so no conversion is needed at call time.
    defp prefix_multiplier(nil), do: 1.0
    defp prefix_multiplier(prefix), do: Map.get(@si_prefixes, prefix, 1.0)

    defp power_exponent(nil), do: 1
    defp power_exponent(:square), do: 2
    defp power_exponent(:cubic), do: 3
    defp power_exponent({:pow, n}), do: n
  '''

  # The generated file records how it was produced, so a regeneration after a
  # CLDR update reproduces exactly the same table.
  defp render(module, aliases) do
    """
    # Generated by `mix localize.unit.gen_conversions`. Do not edit.
    #
    # CLDR: #{Localize.version()}
    #
    # Regenerate with:
    #
    #     mix localize.unit.gen_conversions --module #{module}
    #
    # This file is generated from Localize (https://hex.pm/packages/localize)
    # and carries two licenses. The code — the unit parser and the conversion
    # logic — is Localize's, under the Apache License 2.0. The conversion
    # factors, base units and unit spellings are data from the Unicode Common
    # Locale Data Repository (CLDR), under the Unicode License v3.
    #
    # SPDX-FileCopyrightText: Copyright Kip Cole
    # SPDX-FileCopyrightText: Copyright © 1991-2026 Unicode, Inc.
    # SPDX-License-Identifier: Apache-2.0 AND Unicode-3.0
    #
    # The Unicode license requires its copyright and permission notice to
    # accompany copies of the data or appear in associated documentation. It
    # is reproduced in the "Unicode Data" section of Localize's LICENSE.md:
    # https://github.com/elixir-localize/localize/blob/main/LICENSE.md

    #{parser_source(module)}
    defmodule #{module} do
      @moduledoc \"\"\"
      Converts units to their base units. Generated from CLDR data by
      Localize; has no runtime dependencies.

      Every unit `Localize.Unit` converts is converted here — defined units,
      SI-prefixed units, powers, and `-per-` and juxtaposed compounds — to
      the same canonical base unit, with the same factor.

      Conversion is affine — `base = value * factor + offset` — so both
      scaled units (kilometers) and offset units (degrees Celsius) are
      handled. Two things are refused rather than approximated: a unit whose
      scale is not affine, such as `beaufort`, which no factor and offset can
      express — this one Localize does convert, through a scale this module
      cannot represent; and a mixed unit, such as `foot-and-inch`, which is a
      way of displaying a quantity rather than a unit to convert, and which
      Localize declines to convert either.

      \"\"\"

    #{render_conversions()}

    #{render_factors()}

    #{render_base_units()}

    #{render_prefixes()}

    #{render_aliases(aliases)}

    #{@runtime_body}
    end
    """
  end

  # unit => the base unit string CLDR converts it to, which may itself be a
  # compound ("square-meter", "kilogram-meter-per-square-second").
  defp render_conversions do
    Data.conversions()
    |> Enum.sort()
    |> map_literal("@conversions", fn base -> inspect(base) end)
  end

  # unit => {factor, offset}. CLDR marks a non-affine scale as `:special`;
  # it is emitted verbatim so the generated module can refuse it by name
  # rather than compute a wrong number from a missing entry.
  defp render_factors do
    Data.conversion_factors()
    |> Enum.sort()
    |> map_literal("@factors", fn %{factor: factor, offset: offset} ->
      "{#{number_literal(factor)}, #{number_literal(offset * 1.0)}}"
    end)
  end

  # CLDR's conversion factors include values like 149597870700.0, and Credo's
  # `Readability.LargeNumbers` flags any literal of five or more digits written
  # without separators. The generated file is committed and linted in the
  # caller's project, so the separators are emitted here rather than left for
  # every consumer to exempt the file.
  defp number_literal(number) when is_integer(number) or is_float(number) do
    case inspect(number) do
      "-" <> magnitude -> "-" <> group_leading_digits(magnitude)
      magnitude -> group_leading_digits(magnitude)
    end
  end

  # Not every factor is a number: `:special` marks a conversion the factor
  # table cannot express, and it is emitted unchanged.
  defp number_literal(other), do: inspect(other)

  # Only the integer part is grouped: a fractional tail or an exponent must be
  # left alone, and `inspect/1` puts the integer part first in both forms.
  defp group_leading_digits(text) do
    case Regex.run(~r/^(\d{5,})(.*)$/s, text, capture: :all_but_first) do
      [digits, rest] -> underscore_digits(digits) <> rest
      nil -> text
    end
  end

  defp underscore_digits(digits) do
    digits
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1_")
    |> String.reverse()
  end

  # The irreducible units every conversion bottoms out in. `_by_length` drives
  # longest-match tokenizing of compound base strings, whose parts are
  # hyphen-joined and may themselves contain hyphens; the order map fixes the
  # canonical order CLDR writes a recomposed base unit in.
  defp render_base_units do
    units = Data.simple_base_units()

    by_length = Enum.sort_by(units, &(-String.length(&1)))

    order =
      units
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {unit, index} -> "    #{inspect(unit)} => #{index}," end)

    """
      @simple_base_units #{inspect(Enum.sort(units))}

      @simple_base_units_by_length #{inspect(by_length)}

      @simple_unit_order %{
    #{order}
      }\
    """
  end

  defp render_prefixes do
    Data.si_prefix_multipliers()
    |> Enum.map(fn {name, multiplier} -> {Data.si_prefix_atom(name), multiplier} end)
    |> Enum.sort()
    |> map_literal("@si_prefixes", &number_literal/1)
  end

  defp render_aliases(aliases) do
    aliases
    |> Enum.sort()
    |> map_literal("@aliases", &inspect/1)
  end

  defp map_literal(pairs, name, format_value) do
    rows =
      Enum.map_join(pairs, "\n", fn {key, value} ->
        "    #{inspect(key)} => #{format_value.(value)},"
      end)

    "  #{name} %{\n#{rows}\n  }"
  end
end
