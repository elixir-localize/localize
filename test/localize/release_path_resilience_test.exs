defmodule Localize.ReleasePathResilienceTest do
  use ExUnit.Case, async: true

  # Regression: `Application.app_dir/2` evaluated inside a module attribute
  # bakes the build host's absolute path into the compiled BEAM. A Mix release
  # built on one host and run on another (e.g. CI runner -> Fly machine) then
  # crashes at boot when the runtime tries to read that frozen path:
  #
  #     ** (File.Error) could not read file
  #        "/home/runner/work/.../_build/dev/lib/localize/priv/localize/
  #         supplemental_data/number_systems.etf": no such file or directory
  #
  # Module attributes that need the path at *runtime* must call
  # `Application.app_dir/2` from inside a function body so the lookup happens
  # against the runtime application controller, not the compile-time one.
  describe "ETF data paths used at runtime" do
    test "Localize.Number.System does not bake an absolute priv path into the BEAM" do
      absolute =
        Application.app_dir(
          :localize,
          "priv/localize/supplemental_data/number_systems.etf"
        )

      beam_bytes =
        Localize.Number.System
        |> beam_path()
        |> File.read!()

      refute String.contains?(beam_bytes, absolute),
             """
             Localize.Number.System has the absolute path

                 #{absolute}

             baked into its compiled BEAM. This means a release built on this
             host will crash at boot on any other host. The path must be
             resolved at runtime via `Application.app_dir/2` called from a
             function body, not from a module attribute.
             """
    end
  end

  # Under `mix test --cover` `:code.which/1` returns `:cover_compiled`
  # instead of a path; resolve the on-disk beam directly so this
  # regression check also runs under coverage.
  defp beam_path(module) do
    case :code.which(module) do
      :cover_compiled ->
        Path.join([Application.app_dir(:localize), "ebin", "#{module}.beam"])

      path ->
        path
    end
  end
end
