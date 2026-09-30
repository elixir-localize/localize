defmodule Localize.Data.CldrJsonTest do
  @moduledoc """
  Covers the stamp a CLDR JSON build writes and the check of its options.
  The build itself needs Maven and a CLDR checkout, so it is exercised by
  `mix localize.build_cldr_json`, not here.

  """

  use ExUnit.Case, async: true

  alias Localize.Data.CldrJson

  @current_options """
  converter -m .* -p true -o true -r true -s contributed -n true
  production_data --keepPreBasic false
  types main supplemental rbnf
  """

  @moduletag :tmp_dir

  test "reads a stamp", %{tmp_dir: tmp_dir} do
    File.write!(Path.join(tmp_dir, "localize_build.txt"), """
    commit 6198cae999ceb4847b25ddc0815835f07fced411
    describe release-49-beta2-5-g6198cae999
    #{@current_options}\
    """)

    stamp = CldrJson.stamp(tmp_dir)

    assert stamp["commit"] == "6198cae999ceb4847b25ddc0815835f07fced411"
    assert stamp["describe"] == "release-49-beta2-5-g6198cae999"
    assert stamp["converter"] == "-m .* -p true -o true -r true -s contributed -n true"
    assert CldrJson.current_options?(stamp)
  end

  test "a directory without a stamp has none", %{tmp_dir: tmp_dir} do
    assert CldrJson.stamp(tmp_dir) == nil
    assert CldrJson.stamp(Path.join(tmp_dir, "absent")) == nil
  end

  test "a stamp from other options is not current", %{tmp_dir: tmp_dir} do
    File.write!(Path.join(tmp_dir, "localize_build.txt"), """
    commit 6198cae999ceb4847b25ddc0815835f07fced411
    #{String.replace(@current_options, "-n true", "-n false")}\
    """)

    refute CldrJson.current_options?(CldrJson.stamp(tmp_dir))
  end

  test "tolerates a malformed stamp", %{tmp_dir: tmp_dir} do
    File.write!(Path.join(tmp_dir, "localize_build.txt"), "garbage\n\n \u0000")

    stamp = CldrJson.stamp(tmp_dir)

    assert is_map(stamp)
    refute CldrJson.current_options?(stamp)
  end
end
