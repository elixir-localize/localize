defmodule Localize.Gettext.MigrationTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Localize.Gettext.{Interpolation, Migration}

  doctest Localize.Gettext.Migration

  @catalog ~S'''
  msgid ""
  msgstr ""
  "Language: fr\n"
  "Plural-Forms: nplurals=2; plural=(n > 1);\n"

  #: lib/my_app/accounts.ex:12
  msgid "can't be blank"
  msgstr "doit être renseigné"

  msgid "should be at least %{count} character(s)"
  msgstr "doit contenir au moins %{count} caractère(s)"

  msgctxt "admin"
  msgid "Hello %{name}"
  msgstr "Bonjour %{name}"

  msgid "%{count} file"
  msgid_plural "%{count} files"
  msgstr[0] "%{count} fichier"
  msgstr[1] "%{count} fichiers"

  msgid "must be one of {a, b}: %{value}"
  msgstr ""

  msgid ".markup"
  msgstr ""

  msgid "  indented %{value}"
  msgstr ""

  msgid "price %{1x} odd"
  msgstr ""

  msgid "A rating can name a variable, such as {{post.rating}}."
  msgstr ""

  msgid "{{Already {$name} MF2}}"
  msgstr ""

  #~ msgid "Old %{thing}"
  #~ msgstr "Vieux %{thing}"
  '''

  defp catalog do
    {:ok, catalog} = Expo.PO.parse_string(@catalog)
    catalog
  end

  defp strings(%Expo.Messages{messages: messages}) do
    Enum.flat_map(messages, fn
      %Expo.Message.Singular{msgid: msgid, msgstr: msgstr} ->
        [IO.iodata_to_binary(msgid), IO.iodata_to_binary(msgstr)]

      %Expo.Message.Plural{msgid: msgid, msgid_plural: plural, msgstr: msgstrs} ->
        forms =
          msgstrs
          |> Enum.sort()
          |> Enum.map(fn {_index, string} -> IO.iodata_to_binary(string) end)

        [IO.iodata_to_binary(msgid), IO.iodata_to_binary(plural) | forms]
    end)
  end

  test "rewrites Gettext's placeholders as MF2 variables in msgids, plural msgids and msgstrs" do
    {:ok, converted, _renames} = Migration.convert(catalog())
    by_msgid = Map.new(converted.messages, &{IO.iodata_to_binary(&1.msgid), &1})

    assert IO.iodata_to_binary(by_msgid["should be at least {$count} character(s)"].msgstr) ==
             "doit contenir au moins {$count} caractère(s)"

    plural = by_msgid["{$count} file"]
    assert IO.iodata_to_binary(plural.msgid_plural) == "{$count} files"

    assert Enum.map(Enum.sort(plural.msgstr), fn {_i, s} -> IO.iodata_to_binary(s) end) == [
             "{$count} fichier",
             "{$count} fichiers"
           ]

    assert IO.iodata_to_binary(by_msgid["Hello {$name}"].msgctxt) == "admin"
    assert IO.iodata_to_binary(by_msgid["Old {$thing}"].msgstr) == "Vieux {$thing}"
    assert by_msgid["Old {$thing}"].obsolete
  end

  test "escapes and quotes text where MF2 needs it, and keeps what is already valid MF2" do
    {:ok, converted, _renames} = Migration.convert(catalog())
    msgids = Enum.map(converted.messages, &IO.iodata_to_binary(&1.msgid))

    assert "can't be blank" in msgids
    assert ~S"must be one of \{a, b\}: {$value}" in msgids
    assert "{{.markup}}" in msgids
    assert "{{  indented {$value}}}" in msgids
    assert ~S"price %\{1x\} odd" in msgids
    assert ~S"A rating can name a variable, such as \{\{post.rating\}\}." in msgids
    assert "{{Already {$name} MF2}}" in msgids
  end

  test "lists each renamed msgid with its context, in order" do
    {:ok, _converted, renames} = Migration.convert(catalog())

    assert %{context: "admin", from: "Hello %{name}", to: "Hello {$name}"} in renames
    assert %{context: nil, from: "%{count} files", to: "{$count} files"} in renames
    assert %{context: nil, from: ".markup", to: "{{.markup}}"} in renames
    refute Enum.any?(renames, &(&1.from == "can't be blank"))

    assert Enum.map(renames, & &1.from) |> Enum.take(2) == [
             "should be at least %{count} character(s)",
             "Hello %{name}"
           ]
  end

  test "gives strings that are valid MF2 and format as the originals did" do
    {:ok, converted, _renames} = Migration.convert(catalog())

    capture_log(fn ->
      for {from, to} <- Enum.zip(strings(catalog()), strings(converted)) do
        bindings = Map.new(Regex.scan(~r/%\{([^{}]*)\}/, from), fn [_, name] -> {name, "V"} end)

        assert {:ok, _parsed} = Localize.Message.parse(to), inspect(to)

        assert Interpolation.runtime_interpolate(to, bindings) ==
                 Interpolation.runtime_interpolate(from, bindings),
               inspect({from, to})
      end
    end)
  end

  test "is idempotent, and keeps the header and a catalog with nothing to convert as it was" do
    {:ok, converted, _renames} = Migration.convert(catalog())
    {:ok, again, renames} = Migration.convert(converted)

    assert renames == []
    assert again == converted
    assert converted.headers == catalog().headers

    plain =
      Expo.PO.parse_string!(~S'''
      msgid "can't be blank"
      msgstr "doit être renseigné"
      ''')

    assert {:ok, ^plain, []} = Migration.convert(plain)
    assert IO.iodata_to_binary(Expo.PO.compose(converted)) =~ ~S|msgid "Hello {$name}"|
  end

  test "returns an error, never raises, for anything but a catalog" do
    for value <- [nil, "msgid", %{}, [catalog()]] do
      assert {:error, %Localize.InvalidValueError{}} = Migration.convert(value)
    end
  end
end
