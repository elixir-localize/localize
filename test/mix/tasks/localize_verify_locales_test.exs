defmodule Mix.Tasks.Localize.VerifyLocalesTest do
  @moduledoc """
  Covers the task that checks locale files against the bundled hash manifest.

  The manifest pins the locale data to the shape this release's accessors were
  written against, so the hashes are deliberately not overridable (issue #59).
  That makes two things load-bearing: the task must fail on bytes the pipeline
  did not produce, and it must name the CLDR repository tag the reference
  bytes came from, which is the only actionable way out of a mismatch.

  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Localize.VerifyLocales

  # Three published locales, enough to cover a verified file beside a failing
  # one without copying all 657.
  @locales ["en", "fr", "ja"]

  defp published_dir, do: Path.join(Localize.Priv.dir(), "localize/locales")

  defp stage(tmp_dir, locales \\ @locales) do
    for locale <- locales do
      File.cp!(Path.join(published_dir(), "#{locale}.etf"), Path.join(tmp_dir, "#{locale}.etf"))
    end

    tmp_dir
  end

  # Failing files are reported on stderr, which `capture_io/1` does not take.
  # Wrapping both streams keeps a deliberate failure out of the suite output.
  defp silently(fun), do: capture_io(:stderr, fn -> capture_io(fun) end)

  describe "a directory of published files" do
    @tag :tmp_dir
    test "verifies every file and reports no failures", %{tmp_dir: tmp_dir} do
      output = capture_io(fn -> VerifyLocales.run([stage(tmp_dir)]) end)

      assert output =~ "3 verified"
      assert output =~ "0 mismatched"
      assert output =~ "0 not in manifest"
      assert output =~ "All files verify against the bundled manifest."
    end

    @tag :tmp_dir
    test "counts the manifest entries with no file present", %{tmp_dir: tmp_dir} do
      output = capture_io(fn -> VerifyLocales.run([stage(tmp_dir)]) end)

      assert output =~ ~r/\d+ of \d+ manifest entries have no file here/
    end

    @tag :tmp_dir
    test "--quiet drops the per-file lines but keeps the summary", %{tmp_dir: tmp_dir} do
      directory = stage(tmp_dir)

      loud = capture_io(fn -> VerifyLocales.run([directory]) end)
      quiet = capture_io(fn -> VerifyLocales.run([directory, "--quiet"]) end)

      assert loud =~ "ok               en"
      refute quiet =~ "ok               en"
      assert quiet =~ "3 verified"
    end
  end

  describe "provenance" do
    @tag :tmp_dir
    test "names the CLDR repo tag the reference files were generated from",
         %{tmp_dir: tmp_dir} do
      output = capture_io(fn -> VerifyLocales.run([stage(tmp_dir)]) end)

      assert output =~ "CLDR repo tag:"
      assert output =~ Localize.cldr_repo_ref()
    end

    @tag :tmp_dir
    test "names the CLDR version, the Localize version and the reference CDN",
         %{tmp_dir: tmp_dir} do
      output = capture_io(fn -> VerifyLocales.run([stage(tmp_dir)]) end)

      assert output =~ "CLDR version:      #{Localize.version()}"
      assert output =~ "Localize version:  #{Application.spec(:localize, :vsn)}"
      assert output =~ Localize.Locale.Provider.base_url()
      assert output =~ Localize.Locale.Provider.version_segment()
    end
  end

  describe "bytes the pipeline did not produce" do
    @tag :tmp_dir
    test "a tampered file fails the task and is named", %{tmp_dir: tmp_dir} do
      directory = stage(tmp_dir)
      File.write!(Path.join(directory, "fr.etf"), "tampered", [:append])

      assert_raise Mix.Error, ~r/1 file\(s\).*do not match the bundled manifest/s, fn ->
        silently(fn -> VerifyLocales.run([directory, "--quiet"]) end)
      end
    end

    @tag :tmp_dir
    test "the failure names the CLDR tag to rebuild from", %{tmp_dir: tmp_dir} do
      directory = stage(tmp_dir)
      File.write!(Path.join(directory, "fr.etf"), "tampered", [:append])

      error =
        assert_raise Mix.Error, fn ->
          silently(fn -> VerifyLocales.run([directory, "--quiet"]) end)
        end

      assert error.message =~ Localize.cldr_repo_ref()
      assert error.message =~ "mix localize.download_locales --force"
      assert error.message =~ "not overridable"
    end

    @tag :tmp_dir
    test "a file named after something that is not a locale fails the task",
         %{tmp_dir: tmp_dir} do
      directory = stage(tmp_dir)
      File.cp!(Path.join(published_dir(), "en.etf"), Path.join(directory, "notalocale.etf"))

      assert_raise Mix.Error, ~r/do not match the bundled manifest/, fn ->
        silently(fn -> VerifyLocales.run([directory, "--quiet"]) end)
      end
    end

    @tag :tmp_dir
    test "a file not in the manifest does not become an atom", %{tmp_dir: tmp_dir} do
      directory = stage(tmp_dir)
      name = "zz-notalocale-#{System.unique_integer([:positive])}"
      File.cp!(Path.join(published_dir(), "en.etf"), Path.join(directory, "#{name}.etf"))

      assert_raise Mix.Error, fn ->
        silently(fn -> VerifyLocales.run([directory, "--quiet"]) end)
      end

      assert Localize.Utils.Helpers.existing_atom(name) == nil
    end
  end

  describe "arguments" do
    @tag :tmp_dir
    test "an empty directory is refused rather than reported as verified",
         %{tmp_dir: tmp_dir} do
      assert_raise Mix.Error, ~r/no \.etf files found/, fn ->
        capture_io(fn -> VerifyLocales.run([tmp_dir]) end)
      end
    end

    test "a path that is not a directory is refused" do
      assert_raise Mix.Error, ~r/is not a directory/, fn ->
        capture_io(fn -> VerifyLocales.run(["/nonexistent/localize-verify-test"]) end)
      end
    end

    test "more than one directory is refused" do
      assert_raise Mix.Error, ~r/expected at most one directory/, fn ->
        capture_io(fn -> VerifyLocales.run(["one", "two"]) end)
      end
    end
  end

  describe "the recorded CLDR repo tag" do
    test "is readable from priv" do
      assert is_binary(Localize.cldr_repo_ref())
      refute Localize.cldr_repo_ref() == ""
    end

    test "ships in the hex package" do
      # The task's whole remedy depends on the tag reaching users, and nothing
      # else in the suite would notice its absence from the package.
      assert "priv/localize/cldr_repo_ref" in Mix.Project.config()[:package][:files]
    end
  end
end
