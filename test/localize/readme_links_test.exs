defmodule Localize.ReadmeLinksTest do
  @moduledoc """
  The README's links to source files carry the version in their path, and
  nothing regenerates them — unlike the `mix.exs` package links, which
  interpolate `@version`. They were left pointing at the previous release
  twice in a row, once serving a LICENSE that predated the change the release
  was about, so the check is here rather than in a reviewer's memory.

  """

  use ExUnit.Case, async: true

  @source_links ~r{https://github\.com/elixir-localize/localize/blob/v([0-9]+\.[0-9]+\.[0-9]+)/}

  test "every versioned source link points at the current version" do
    version = Localize.MixProject.project()[:version]
    readme = File.read!(Path.join(__DIR__, "../../README.md"))

    stale =
      @source_links
      |> Regex.scan(readme)
      |> Enum.map(fn [_match, pinned] -> pinned end)
      |> Enum.uniq()
      |> Enum.reject(&(&1 == version))

    assert stale == [],
           "README links to v#{Enum.join(stale, ", v")} but the package is v#{version}. " <>
             "Update the blob/v… paths in README.md to v#{version}."
  end

  test "guide and module links resolve to hexdocs rather than GitHub" do
    # A GitHub blob link drops the reader out of the rendered documentation
    # into raw markdown. Only genuine source files with no hexdocs page — the
    # licence, the skill definition — belong on GitHub.
    readme = File.read!(Path.join(__DIR__, "../../README.md"))

    offenders =
      ~r{https://github\.com/elixir-localize/localize/blob/v[0-9.]+/([^\s\)]+)}
      |> Regex.scan(readme)
      |> Enum.map(fn [_match, path] -> path end)
      |> Enum.reject(&(&1 in ["LICENSE.md", "skills/localize/SKILL.md"]))

    assert offenders == [],
           "These README links go to GitHub but have a rendered hexdocs page: " <>
             Enum.join(offenders, ", ")
  end
end
