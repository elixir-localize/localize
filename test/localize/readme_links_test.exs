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
    expected = expected_link_version(version)
    readme = File.read!(Path.join(__DIR__, "../../README.md"))

    stale =
      @source_links
      |> Regex.scan(readme)
      |> Enum.map(fn [_match, pinned] -> pinned end)
      |> Enum.uniq()
      |> Enum.reject(&(&1 == expected))

    assert stale == [],
           "README links to v#{Enum.join(stale, ", v")} but should link to v#{expected} " <>
             "(the package is v#{version}). Update the blob/v... paths in README.md."
  end

  # A pre-release version is never tagged, so a link pinned to it would 404 —
  # and `@source_links` would not even match it, silently retiring this check.
  # While `@version` carries a pre-release suffix the links stay on the last
  # released version, and the moment the suffix is dropped for the release the
  # check demands the new one.
  defp expected_link_version(version) do
    case String.split(version, "-", parts: 2) do
      [release] -> release
      [_base, _pre_release] -> latest_released_version()
    end
  end

  defp latest_released_version do
    changelog = File.read!(Path.join(__DIR__, "../../CHANGELOG.md"))

    case Regex.run(~r/^## \[([0-9]+\.[0-9]+\.[0-9]+)\]/m, changelog) do
      [_match, version] ->
        version

      nil ->
        flunk("No released `## [x.y.z]` heading found in CHANGELOG.md to pin README links to")
    end
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
