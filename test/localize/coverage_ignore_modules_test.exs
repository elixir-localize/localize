defmodule Localize.CoverageIgnoreModulesTest do
  use ExUnit.Case, async: true

  # The coverage ignore list in mix.exs names modules by atom. A
  # rename (e.g. the leex/yecc modules gaining the localize_ prefix)
  # silently orphans an entry: the renamed module stops being
  # excluded, counts as ~0% covered, and drags the total below the
  # CI threshold with no pointer to the cause. This test makes the
  # drift loud: every atom entry must be a loadable module.
  test "every module atom in the coverage ignore list exists" do
    ignored = Mix.Project.config()[:test_coverage][:ignore_modules]

    missing =
      for module <- ignored,
          is_atom(module),
          not Code.ensure_loaded?(module),
          do: module

    assert missing == [],
           """
           These coverage ignore_modules entries in mix.exs name modules
           that do not exist (renamed or removed?): #{inspect(missing)}
           Update the list or the renamed modules will count as
           uncovered and drop the total below the CI threshold.
           """
  end
end
