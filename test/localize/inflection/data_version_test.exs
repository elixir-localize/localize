defmodule Localize.Inflection.DataVersionTest do
  # The data version segment in the inflection data directory. An
  # artifact of an earlier data version was once indistinguishable from
  # a current one: the download task skipped any file that was already
  # there and `Localize.Inflection.Locale.artifact?/1` reported it
  # present, so a zh artifact predating the Traditional Chinese pronoun
  # table stayed in place and resolved zh-TW to the Simplified table.
  # Addressing artifacts under their data version makes a superseded
  # file unreachable rather than merely detectable.
  #
  # async: false because these tests repoint `:inflection_data_dir`,
  # which is global.
  use ExUnit.Case, async: false

  alias Localize.Inflection.{Data, DataDir, Locale, Provider}

  setup do
    directory =
      Path.join(System.tmp_dir!(), "localize_version_#{System.unique_integer([:positive])}")

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

  test "the data directory is the configured directory plus the data version", %{
    directory: directory
  } do
    assert DataDir.base_dir() == directory
    assert DataDir.dir() == Path.join(directory, Provider.data_version())

    assert DataDir.path("de.etf") ==
             Path.join([directory, Provider.data_version(), "de.etf"])
  end

  test "an artifact of an earlier data version is not reported present", %{
    directory: directory
  } do
    superseded = Path.join(directory, "0000deadbeef-r1")
    File.mkdir_p!(superseded)
    File.write!(Path.join(superseded, "zz-superseded.etf"), :erlang.term_to_binary(%{}))

    refute Locale.artifact?("zz-superseded")
    assert {:error, :enoent} = Data.ensure_loaded(:"zz-superseded")
  end

  test "an artifact of the current data version is reported present" do
    File.mkdir_p!(DataDir.dir())
    File.write!(DataDir.path("zz-current.etf"), :erlang.term_to_binary(%{}))

    assert Locale.artifact?("zz-current")
  end
end
