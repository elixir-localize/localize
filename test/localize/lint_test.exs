defmodule Localize.LintTest do
  use ExUnit.Case, async: true

  # Source-level lint tests that catch fragile patterns the team has
  # been bitten by. These run as part of `mix test` so a CI failure
  # surfaces immediately on the offending PR — there is no separate
  # static-analysis step to wire up.

  @root File.cwd!() |> Path.join("lib")

  describe "no {:ok, _} = Localize.<fallible_call> anti-pattern" do
    # The original bug behind issue #26 (and the underlying anti-pattern
    # that surfaced as a `MatchError` in `mix localize.download_locales`)
    # was a bare `{:ok, _} = Localize.Message.format(...)` against
    # caller-shaped input. Any future `{:ok, ...} =` match on the
    # right-hand side of a fallible Localize call risks the same crash
    # mode. Use `case`, `with`, or `{:ok, _} = ...!` (the bang variant)
    # instead.
    #
    # This test scans `lib/` and fails if any new offender appears.
    # The empty allowlist below is deliberate: every existing instance
    # was fixed when the test was introduced. If a legitimate new use
    # arises (e.g. operating on bundled, never-failing data), justify
    # it in a comment at the site and add the file/line tuple to
    # `@allowed`.

    # Localize calls whose `{:ok, _}` result is unsafe to pattern-match
    # against because they can return `{:error, _}` on caller-controlled
    # input, locale fallback, or downstream data lookups.
    @unsafe_calls [
      "Localize.Message.format",
      "Localize.Message.format_to_iolist",
      "Localize.Message.format_to_safe_list",
      "Localize.Number.parse",
      "Localize.Number.to_string",
      "Localize.Date.to_string",
      "Localize.Time.to_string",
      "Localize.DateTime.to_string",
      "Localize.Interval.to_string",
      "Localize.Duration.to_string",
      "Localize.Unit.to_string",
      "Localize.Unit.new",
      "Localize.Unit.parse",
      "Localize.Unit.Parser.parse",
      "Localize.List.to_string",
      "Localize.LanguageTag.parse",
      "Localize.LanguageTag.new",
      "Localize.Locale.new",
      "Localize.Locale.get",
      "Localize.Locale.parent",
      "Localize.validate_locale"
    ]

    # File/line pairs that have been reviewed and are known-safe.
    # Add new entries with a justification comment on the line.
    @allowed []

    test "no source file pattern-matches {:ok, _} = <unsafe Localize call>" do
      offenders =
        @root
        |> all_elixir_files()
        |> Enum.flat_map(&scan_file/1)
        |> Enum.reject(fn {file, line, _snippet} -> {file, line} in @allowed end)

      assert offenders == [],
             "\n\nFragile `{:ok, _} = <Localize call>` matches found:\n\n" <>
               Enum.map_join(offenders, "\n", fn {file, line, snippet} ->
                 "  #{Path.relative_to(file, File.cwd!())}:#{line}\n    #{snippet}"
               end) <>
               "\n\nAny one of these can crash the calling process with a " <>
               "`MatchError` when the fallible call returns `{:error, _}`. " <>
               "Use `case`, `with`, or the bang variant of the function " <>
               "instead. See `test/localize/lint_test.exs` for context."
    end

    defp scan_file(path) do
      path
      |> File.stream!()
      |> Stream.with_index(1)
      |> Stream.reject(fn {line, _} -> doctest_line?(line) end)
      |> Stream.flat_map(fn {line, line_number} ->
        @unsafe_calls
        |> Enum.filter(&match_line?(line, &1))
        |> Enum.map(fn _call -> {path, line_number, String.trim(line)} end)
      end)
      |> Enum.to_list()
    end

    # A line is a doctest example if its first non-space character is
    # the `#` of a comment OR it starts with `iex>` / `...>` after
    # leading whitespace.
    defp doctest_line?(line) do
      trimmed = String.trim_leading(line)

      String.starts_with?(trimmed, "iex>") or String.starts_with?(trimmed, "...>") or
        String.starts_with?(trimmed, "#")
    end

    defp match_line?(line, call) do
      # Match `{:ok, ...} = <call>(` allowing single-line patterns
      # only. Multi-line tuple patterns are rare and we accept the
      # false-negative trade-off.
      Regex.match?(~r/\{\s*:ok\s*,[^}]+\}\s*=\s*#{Regex.escape(call)}\s*\(/, line)
    end

    defp all_elixir_files(root) do
      root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
    end
  end

  describe "no compile-time-frozen Application.app_dir/2 in a module attribute" do
    # Issue #28: storing `Application.app_dir/2` in a module attribute
    # bakes the build host's absolute path into the compiled BEAM. A
    # Mix release built on one host and run on another then crashes on
    # any runtime read of that attribute, because the path doesn't
    # exist on the target machine.
    #
    # The safe patterns are either (a) inline the `Application.app_dir/2`
    # call at each compile-time use site so no attribute survives, or
    # (b) wrap the lookup in a function body so it resolves against the
    # runtime application controller.
    #
    # This lint catches new `@<something>_path Application.app_dir(`
    # declarations in `lib/` before they ship.

    test "no source file declares `@<name>_path Application.app_dir(...)`" do
      offenders =
        File.cwd!()
        |> Path.join("lib")
        |> Path.join("**/*.ex")
        |> Path.wildcard()
        |> Enum.flat_map(&scan_app_dir_attribute/1)

      assert offenders == [],
             "\n\nCompile-time-frozen `Application.app_dir/2` declarations " <>
               "found:\n\n" <>
               Enum.map_join(offenders, "\n", fn {file, line, snippet} ->
                 "  #{Path.relative_to(file, File.cwd!())}:#{line}\n    #{snippet}"
               end) <>
               "\n\nEach of these bakes the build host's absolute path " <>
               "into the compiled BEAM and crashes on any release shipped " <>
               "to a different host. Either inline `Application.app_dir/2` " <>
               "at the use site, or wrap the lookup in a function body. " <>
               "See `test/localize/lint_test.exs` for context."
    end

    defp scan_app_dir_attribute(path) do
      path
      |> File.stream!()
      |> Stream.with_index(1)
      |> Stream.filter(fn {line, _} ->
        Regex.match?(~r/^\s*@\w+_path\s+Application\.app_dir\s*\(/, line)
      end)
      |> Enum.map(fn {line, line_number} -> {path, line_number, String.trim(line)} end)
    end
  end

  describe "an @on_load callback's Localize modules are compiled first" do
    # A module's `@on_load` callback runs when the module is loaded, in a
    # process of the code server's, where the compiler cannot see what it
    # calls. A compiler before Elixir 1.19 loads a module as soon as it is
    # compiled, so a callback that calls another module of this project
    # fails with `:undef` whenever that module is compiled later:
    # `Localize.Nif`'s called `Localize.Priv.path/1`, and every build on
    # Elixir 1.17 and 1.18 logged "The on_load function for module
    # Elixir.Localize.Nif returned: {:undef, …}". From Elixir 1.19 a module
    # is loaded when it is first used, and the same callback fails the
    # build once the module is used while Localize compiles.
    #
    # `Code.ensure_compiled!/1` in the module's body has the compiler
    # compile and load the other module first. A `require` orders the two
    # as well, but Elixir 1.19 warns that a `require` no macro uses is
    # unused, and CI compiles with `--warnings-as-errors`.
    #
    # This lint reads every module with an `@on_load` callback and fails
    # when the callback, or a function of its module that it calls, calls
    # a `Localize` module the body does not ensure.

    test "every Localize module an @on_load callback calls is ensured in the module's body" do
      sources =
        for path <- Path.wildcard(Path.join(File.cwd!(), "lib/**/*.ex")),
            source = File.read!(path),
            String.contains?(source, "@on_load"),
            do: {path, source}

      # `Localize.Nif` is the module the lint was written for: were it not
      # read, the lint would pass by finding nothing.
      assert Enum.any?(sources, fn {path, _source} -> Path.basename(path) == "nif.ex" end)

      offenders =
        for {path, source} <- sources,
            module <- unensured_on_load_calls(source),
            do: {path, module}

      assert offenders == [],
             "\n\n`@on_load` callbacks that call a Localize module the compiler " <>
               "is not told to compile first:\n\n" <>
               Enum.map_join(offenders, "\n", fn {file, module} ->
                 "  #{Path.relative_to(file, File.cwd!())} calls #{module}"
               end) <>
               "\n\nCall `Code.ensure_compiled!/1` with each in the module's body, " <>
               "above `@on_load`. See `test/localize/lint_test.exs` for context."
    end

    # The lint itself, on the shapes it must tell apart: a call written in
    # full, through an alias and through a function of the module, each
    # ensured or not.
    test "the lint finds a call that is not ensured, and no call that is" do
      callback = """
        @on_load :init
        def init, do: load(path())
        defp path, do: Localize.Priv.path("nif")
        defp load(path), do: :erlang.load_nif(path, 0)
        def later, do: Localize.Other.thing()
      """

      assert unensured_on_load_calls("defmodule Localize.A do\n#{callback}end") ==
               ["Localize.Priv"]

      assert unensured_on_load_calls("""
             defmodule Localize.A do
               Code.ensure_compiled!(Localize.Priv)
             #{callback}end
             """) == []

      assert unensured_on_load_calls("""
             defmodule Localize.A do
               require Localize.Priv
             #{callback}end
             """) == []

      aliased = """
        alias Localize.{Priv, Other}
        @on_load {:init, 0}
        def init, do: Priv.path("nif") |> Other.load()
      """

      assert unensured_on_load_calls("defmodule Localize.A do\n#{aliased}end") ==
               ["Localize.Other", "Localize.Priv"]

      assert unensured_on_load_calls("""
             defmodule Localize.A do
               Code.ensure_compiled!(Localize.Priv)
               Code.ensure_compiled!(Localize.Other)
             #{aliased}end
             """) == []

      own = """
        @on_load :init
        def init, do: Localize.A.setup() && __MODULE__.setup() && String.length("a")
        def setup, do: :ok
      """

      assert unensured_on_load_calls("defmodule Localize.A do\n#{own}end") == []

      assert unensured_on_load_calls("defmodule Localize.A do\n  def a, do: Localize.B.b()\nend") ==
               []
    end

    # The `Localize` modules that a source's `@on_load` callbacks call and
    # its body does not ensure, as their names, sorted.
    defp unensured_on_load_calls(source) do
      ast = Code.string_to_quoted!(source)
      aliases = aliases(ast)
      functions = functions(ast)
      ensured = ensured(ast, aliases) ++ defined(ast)

      ast
      |> on_load_callbacks()
      |> reachable(functions)
      |> Enum.flat_map(&Map.get(functions, &1, []))
      |> remote_modules(aliases)
      |> Enum.filter(&match?([:Localize | _], &1))
      |> Enum.reject(&(&1 in ensured))
      |> Enum.map(&Enum.join(&1, "."))
      |> Enum.uniq()
      |> Enum.sort()
    end

    defp collect(ast, collector) do
      {_ast, collected} =
        Macro.prewalk(ast, [], fn node, collected -> {node, collector.(node) ++ collected} end)

      collected
    end

    defp on_load_callbacks(ast) do
      collect(ast, fn
        {:@, _, [{:on_load, _, [name]}]} when is_atom(name) -> [name]
        {:@, _, [{:on_load, _, [{name, 0}]}]} when is_atom(name) -> [name]
        _node -> []
      end)
    end

    # Each function of the source, by name, with its clauses' bodies.
    defp functions(ast) do
      ast
      |> collect(fn
        {kind, _, [{:when, _, [{name, _, _arguments}, _guard]}, body]}
        when kind in [:def, :defp] and is_atom(name) ->
          [{name, body}]

        {kind, _, [{name, _, _arguments}, body]} when kind in [:def, :defp] and is_atom(name) ->
          [{name, body}]

        _node ->
          []
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    end

    # The callbacks and every function of the module they call, in turn.
    defp reachable(names, functions, seen \\ [])
    defp reachable([], _functions, seen), do: seen

    defp reachable([name | names], functions, seen) do
      if name in seen,
        do: reachable(names, functions, seen),
        else: reachable(local_calls(name, functions) ++ names, functions, [name | seen])
    end

    # The functions of the module that its function `name` calls.
    defp local_calls(name, functions) do
      functions
      |> Map.get(name, [])
      |> collect(fn
        {local, _, arguments}
        when is_atom(local) and is_list(arguments) and is_map_key(functions, local) ->
          [local]

        _node ->
          []
      end)
    end

    # The modules whose functions the bodies call, as lists of alias
    # segments, each alias of the source written out in full.
    defp remote_modules(bodies, aliases) do
      collect(bodies, fn
        {{:., _, [{:__aliases__, _, segments}, function]}, _, arguments}
        when is_atom(function) and is_list(arguments) ->
          [expand(segments, aliases)]

        _node ->
          []
      end)
    end

    defp ensured(ast, aliases) do
      collect(ast, fn
        {{:., _, [{:__aliases__, _, [:Code]}, :ensure_compiled!]}, _,
         [{:__aliases__, _, segments}]} ->
          [expand(segments, aliases)]

        {:require, _, [{:__aliases__, _, segments} | _options]} ->
          [expand(segments, aliases)]

        _node ->
          []
      end)
    end

    defp defined(ast) do
      collect(ast, fn
        {:defmodule, _, [{:__aliases__, _, segments}, _body]} -> [segments]
        _node -> []
      end)
    end

    # The source's aliases, each short name with the segments it stands for.
    defp aliases(ast) do
      ast
      |> collect(fn
        {:alias, _, [{:__aliases__, _, segments}]} ->
          [{List.last(segments), segments}]

        {:alias, _, [{:__aliases__, _, segments}, [as: {:__aliases__, _, [short]}]]} ->
          [{short, segments}]

        {:alias, _, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, members}]} ->
          for {:__aliases__, _, member} <- members, do: {List.last(member), base ++ member}

        _node ->
          []
      end)
      |> Map.new()
    end

    defp expand([first | rest] = segments, aliases) do
      case Map.fetch(aliases, first) do
        {:ok, full} -> full ++ rest
        :error -> segments
      end
    end
  end
end
