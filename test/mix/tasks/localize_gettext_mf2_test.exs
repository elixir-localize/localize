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
    refute output =~ "not a string literal"

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

  describe "safety" do
    @errors_catalog ~S"""
    msgid "should be at least %{count} character(s)"
    msgstr ""
    """

    @tag :tmp_dir
    test "leaves a domain looked up with a dynamic msgid unconverted", %{tmp_dir: tmp_dir} do
      stage(tmp_dir)
      write(tmp_dir, "priv/gettext/errors.pot", @errors_catalog)

      write(
        tmp_dir,
        "lib/core_components.ex",
        "def translate_error({msg, opts}), do: Gettext.dgettext(MyApp.Gettext, \"errors\", msg, opts)\n" <>
          "def blank, do: dgettext(\"errors\", \"should be at least %{count} character(s)\", count: 1)\n"
      )

      output = run(tmp_dir, [])

      assert output =~ "core_components.ex:1: the msgid of this call in errors is an expression"
      refute output =~ "--trust errors"
      assert read(tmp_dir, "priv/gettext/errors.pot") == @errors_catalog

      assert read(tmp_dir, "lib/core_components.ex") =~
               ~S|"should be at least %{count} character(s)"|

      assert read(tmp_dir, "priv/gettext/default.pot") =~ ~S|msgid "Hello {$name}"|
    end

    @tag :tmp_dir
    test "converts a domain with a dynamic lookup when it is trusted", %{tmp_dir: tmp_dir} do
      stage(tmp_dir)

      write(
        tmp_dir,
        "lib/titles.ex",
        "@titles %{sign_in: gettext_noop(\"Too many %{things}\")}\n" <>
          "def title(action), do: Gettext.gettext(MyApp.Gettext, Map.fetch!(@titles, action))\n"
      )

      write(
        tmp_dir,
        "priv/gettext/default.pot",
        @catalog <> "\nmsgid \"Too many %{things}\"\nmsgstr \"\"\n"
      )

      untrusted = run(tmp_dir, ["--dry-run"])
      assert untrusted =~ "titles.ex:2: the msgid of this call in default is an expression"
      assert untrusted =~ "--trust default"

      run(tmp_dir, ["--trust", "default"])

      assert read(tmp_dir, "lib/titles.ex") =~ ~S|gettext_noop("Too many {$things}")|
      assert read(tmp_dir, "priv/gettext/default.pot") =~ ~S|msgid "Too many {$things}"|
    end

    @tag :tmp_dir
    test "converts no entry when a call's domain is an expression", %{tmp_dir: tmp_dir} do
      stage(tmp_dir)

      write(
        tmp_dir,
        "lib/translator.ex",
        ~S|def t(domain, msgid), do: Gettext.dgettext(MyApp.Gettext, domain, msgid)|
      )

      output = run(tmp_dir, [])

      assert output =~ "translator.ex:1: the domain of this call is an expression"
      assert output =~ "Catalogs: 0 of 2 changed"
      assert read(tmp_dir, "priv/gettext/default.pot") == @catalog
      assert read(tmp_dir, "lib/page.ex") == @source
    end

    @tag :tmp_dir
    test "keeps an entry whose references name source outside --source", %{tmp_dir: tmp_dir} do
      stage(tmp_dir)

      write(
        tmp_dir,
        "priv/gettext/default.pot",
        ~s|#: lib/page.ex:2\nmsgid "Hello %{name}"\nmsgstr ""\n\n| <>
          ~s|#: ../other_app/lib/other.ex:1\nmsgid "Bye %{name}"\nmsgstr ""\n|
      )

      output =
        capture_io(fn ->
          Mf2.run([
            "--priv",
            Path.join(tmp_dir, "priv/gettext"),
            "--source",
            Path.join(tmp_dir, "lib"),
            "--root",
            tmp_dir
          ])
        end)

      catalog = read(tmp_dir, "priv/gettext/default.pot")

      assert catalog =~ ~S|msgid "Hello {$name}"|
      assert catalog =~ ~S|msgid "Bye %{name}"|
      assert output =~ "1 entries of default are used by source outside the --source directories"
    end
  end
end
