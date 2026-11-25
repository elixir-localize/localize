defmodule Mix.Tasks.Localize.Gettext.Mf2Test do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Localize.Gettext.Mf2

  @catalog ~S'''
  msgid "Hello %{name}"
  msgstr ""

  msgid "can't be blank"
  msgstr ""
  '''

  @translation ~S'''
  msgid "Hello %{name}"
  msgstr "Bonjour %{name}"
  '''

  @source ~S'''
  defmodule Page do
    def greet(name), do: gettext("Hello %{name}", name: name)
    def odd, do: gettext(~s"sigil %{x}")
  end
  '''

  @template ~S|<p>{gettext("Hello %{name}", name: @name)}</p>|

  @plain_source ~S'''
  defmodule Plain do
    def blank, do: dgettext("errors", "can't be blank")
  end
  '''

  defp stage(tmp_dir) do
    write(tmp_dir, "priv/gettext/default.pot", @catalog)
    write(tmp_dir, "priv/gettext/fr/LC_MESSAGES/default.po", @translation)
    write(tmp_dir, "lib/page.ex", @source)
    write(tmp_dir, "lib/page.html.heex", @template)
    write(tmp_dir, "lib/plain.ex", @plain_source)
    write(tmp_dir, "other_app/lib/other.ex", ~S|gettext("Hello %{name}", name: "x")|)
  end

  defp write(tmp_dir, path, content) do
    path = Path.join(tmp_dir, path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end

  defp read(tmp_dir, path) do
    File.read!(Path.join(tmp_dir, path))
  end

  defp run(tmp_dir, arguments) do
    capture_io(fn ->
      Mf2.run([
        "--priv",
        Path.join(tmp_dir, "priv/gettext"),
        "--source",
        Path.join(tmp_dir, "lib") | arguments
      ])
    end)
  end

  @tag :tmp_dir
  test "converts catalogs and source together, reporting what it changed and skipped", %{
    tmp_dir: tmp_dir
  } do
    stage(tmp_dir)
    output = run(tmp_dir, ["--source", Path.join(tmp_dir, "other_app/lib")])

    assert output =~ "Catalogs: 2 of 2 changed, 2 msgids renamed."
    assert output =~ "Source: 3 of 4 files changed, 3 msgids rewritten."
    assert output =~ "page.ex:3: gettext: the msgid is not a string literal"

    assert read(tmp_dir, "priv/gettext/default.pot") =~ ~S|msgid "Hello {$name}"|
    assert read(tmp_dir, "priv/gettext/fr/LC_MESSAGES/default.po") =~ ~S|msgstr "Bonjour {$name}"|
    assert read(tmp_dir, "lib/page.ex") =~ ~S|gettext("Hello {$name}", name: name)|
    assert read(tmp_dir, "lib/page.html.heex") =~ ~S|gettext("Hello {$name}", name: @name)|
    assert read(tmp_dir, "other_app/lib/other.ex") =~ ~S|gettext("Hello {$name}"|
    assert read(tmp_dir, "lib/plain.ex") == @plain_source
  end

  @tag :tmp_dir
  test "writes nothing with --dry-run", %{tmp_dir: tmp_dir} do
    stage(tmp_dir)
    output = run(tmp_dir, ["--dry-run"])

    assert output =~ "Catalogs: 2 of 2 would change"
    assert output =~ "Source: 2 of 3 files would change"
    assert read(tmp_dir, "priv/gettext/default.pot") == @catalog
    assert read(tmp_dir, "lib/page.ex") == @source
  end

  @tag :tmp_dir
  test "changes nothing on a second run", %{tmp_dir: tmp_dir} do
    stage(tmp_dir)
    run(tmp_dir, [])
    catalog = read(tmp_dir, "priv/gettext/default.pot")
    output = run(tmp_dir, [])

    assert output =~ "Catalogs: 0 of 2 changed, 0 msgids renamed."
    assert output =~ "Source: 0 of 3 files changed, 0 msgids rewritten."
    assert read(tmp_dir, "priv/gettext/default.pot") == catalog
  end

  test "refuses an unknown option" do
    assert_raise Mix.Error, ~r/unknown option/, fn -> Mf2.run(["--prov", "x"]) end
  end
end
