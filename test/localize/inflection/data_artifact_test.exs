defmodule Localize.Inflection.DataArtifactTest do
  # Artifacts predating the packed lexicon format. The map and list
  # lexicon shapes were only ever produced by the unreleased r1
  # pipeline, and the code that read them is gone. What must still hold
  # is that meeting one is a reported error rather than a crash —
  # library code never raises.
  #
  # async: false because these tests repoint `:inflection_data_dir`,
  # which is global; a concurrent module loading inflection data would
  # otherwise see the temporary directory.
  use ExUnit.Case, async: false

  alias Localize.Inflection.{Data, DataDir}

  setup do
    directory =
      Path.join(System.tmp_dir!(), "localize_legacy_#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    original = Application.get_env(:localize, :inflection_data_dir)
    Application.put_env(:localize, :inflection_data_dir, directory)

    on_exit(fn ->
      if original do
        Application.put_env(:localize, :inflection_data_dir, original)
      else
        Application.delete_env(:localize, :inflection_data_dir)
      end

      File.rm_rf!(directory)
    end)

    {:ok, directory: directory}
  end

  # The artifact goes where `DataDir` resolves it, which is the
  # configured directory plus the data version segment.
  defp write_artifact(locale, lexicon) do
    artifact = %{
      lexicon: lexicon,
      grammeme_names: {},
      grammeme_bits: %{},
      patterns: {},
      pattern_index: %{},
      features: %{},
      contractions: []
    }

    File.mkdir_p!(DataDir.dir())
    File.write!(DataDir.path("#{locale}.etf"), :erlang.term_to_binary(artifact))
  end

  test "a map-shaped lexicon is reported, not raised" do
    locale = :"zz-legacy-map"
    write_artifact(locale, %{"cat" => {1, [0]}})

    assert {:error, :incompatible_inflection_artifact} = Data.ensure_loaded(locale)
    refute Data.loaded?(locale)
  end

  test "a list-shaped lexicon is reported, not raised" do
    locale = :"zz-legacy-list"
    write_artifact(locale, [{"cat", 1, [0]}])

    assert {:error, :incompatible_inflection_artifact} = Data.ensure_loaded(locale)
    refute Data.loaded?(locale)
  end

  test "a missing artifact is still a plain file error" do
    assert {:error, :enoent} = Data.ensure_loaded(:"zz-absent")
  end

  test "lookup degrades to a miss rather than crashing" do
    locale = :"zz-legacy-lookup"
    write_artifact(locale, %{"cat" => {1, [0]}})

    assert Data.lookup(locale, "cat") == nil
  end
end
