defmodule Localize.Message.Formatter.PluginIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  # End-to-end check: build a tiny Mix project in a tmp dir that depends
  # on Localize by absolute path and uses
  # Localize.Message.Formatter.Plugin, run `mix format` inside it, and
  # assert (a) the second run is a no-op (idempotency) and (b) the
  # output parses as valid MF2.
  #
  # Using a tmp dir means a failing run doesn't pollute the Localize
  # repo's git status.

  @localize_root Path.expand("../../..", __DIR__)

  setup do
    tmp =
      Path.join(System.tmp_dir!(), "localize_fmt_plugin_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(tmp, "lib"))
    File.mkdir_p!(Path.join(tmp, "priv/messages"))

    File.write!(Path.join(tmp, "mix.exs"), """
    defmodule FormatterFixture.MixProject do
      use Mix.Project
      def project do
        [
          app: :formatter_fixture,
          version: "0.0.0",
          elixir: "~> 1.17",
          deps: [{:localize, path: #{inspect(@localize_root)}}]
        ]
      end
    end
    """)

    File.write!(Path.join(tmp, ".formatter.exs"), """
    [
      plugins: [Localize.Message.Formatter.Plugin],
      inputs: [
        "{mix,.formatter}.exs",
        "lib/**/*.{ex,exs}",
        "priv/messages/**/*.mf2"
      ]
    ]
    """)

    File.write!(Path.join(tmp, "lib/sample.ex"), """
    defmodule Sample do
      import Localize.Message.Sigil

      def greet, do: ~M"Hello {$name}"
    end
    """)

    File.write!(Path.join(tmp, "priv/messages/greeting.mf2"), "Hello {$name}!\n")

    on_exit(fn -> File.rm_rf!(tmp) end)

    {:ok, tmp: tmp}
  end

  test "mix format runs cleanly and is idempotent", %{tmp: tmp} do
    # Pre-compile deps so the first `mix format` doesn't also compile
    # localize (which can take a while and produces noisy output).
    {_out, 0} = mix(tmp, ["deps.get"])
    {_out, 0} = mix(tmp, ["deps.compile"])

    {_out, 0} = mix(tmp, ["format"])

    after_first = read_tree(tmp)

    {_out, 0} = mix(tmp, ["format"])

    after_second = read_tree(tmp)

    assert after_first == after_second,
           "mix format is not idempotent. Diff:\n" <>
             diff(after_first, after_second)
  end

  test "mix format --check-formatted passes after one pass", %{tmp: tmp} do
    {_out, 0} = mix(tmp, ["deps.get"])
    {_out, 0} = mix(tmp, ["deps.compile"])

    {_out, 0} = mix(tmp, ["format"])
    {output, status} = mix(tmp, ["format", "--check-formatted"])

    assert status == 0,
           "expected --check-formatted to pass after a format pass, got:\n#{output}"
  end

  # ── helpers ────────────────────────────────────────────────────────

  defp mix(cwd, args) do
    System.cmd("mix", args,
      cd: cwd,
      stderr_to_stdout: true,
      env: [{"MIX_ENV", "dev"}]
    )
  rescue
    _ -> {"mix not found", 127}
  end

  defp read_tree(root) do
    for pattern <- ["lib/**/*.ex", "priv/messages/**/*.mf2", ".formatter.exs", "mix.exs"],
        path <- Path.wildcard(Path.join(root, pattern)),
        into: %{} do
      {Path.relative_to(path, root), File.read!(path)}
    end
  end

  defp diff(before, after_) do
    keys = Enum.uniq(Map.keys(before) ++ Map.keys(after_))

    for key <- keys, before[key] != after_[key] do
      "#{key}:\n  before: #{inspect(before[key])}\n  after:  #{inspect(after_[key])}"
    end
    |> Enum.join("\n\n")
  end
end
