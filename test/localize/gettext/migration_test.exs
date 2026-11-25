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

  describe "convert_source/1" do
    @sample Path.expand("../../support/fixtures/gettext_migration/sample_source.ex.txt", __DIR__)

    defp converted_sample do
      {:ok, converted, report} = Migration.convert_source(File.read!(@sample))
      {converted, report}
    end

    test "rewrites the msgids of every Gettext macro and function" do
      {converted, _report} = converted_sample()

      for line <- [
            ~S|gettext("Hello {$name}", name: "x")|,
            ~S|dgettext("errors", "must be one of \\{a, b\\}: {$value}", value: 1)|,
            ~S|ngettext("{$count} file", "{$count} files", 3)|,
            ~S|dpngettext("d", "ctx", "{$n} x", "{$n} xs", 2, n: 2)|,
            ~S|Gettext.dgettext(MyApp.Gettext, "errors", "is {$x}", x: 1)|,
            ~S|gettext_noop("{{.markup}}")|,
            ~S|gettext("nested {$a}", a: gettext("inner {$b}", b: 1))|,
            ~S|gettext("heredoc {$h}\n")|,
            ~S|gettext("a, b (c) {$d}", d: ?))|,
            ~S|gettext("plain")|,
            ~S|Gettext.dgettext(MyApp.Gettext, "errors", msg, [])|
          ] do
        assert converted =~ line, line
      end
    end

    test "reports a msgid that is not a string literal and holds a placeholder" do
      {converted, report} = converted_sample()

      assert report.rewritten == 13
      assert [%{line: 9, call: "gettext"}, %{line: 18, call: "gettext"}] = report.skipped
      assert converted =~ ~S|gettext(~s"sigil %{x}")|
    end

    test "gives a msgid the conversion its catalog entry gets, and a file that still parses" do
      {converted, _report} = converted_sample()

      assert {:ok, _ast} = Code.string_to_quoted(converted)
      assert {:ok, ^converted, %{rewritten: 0}} = Migration.convert_source(converted)

      {:ok, catalog} =
        Expo.PO.parse_string(~S"""
        msgid "Hello %{name}"
        msgstr ""

        msgid "must be one of {a, b}: %{value}"
        msgstr ""
        """)

      {:ok, catalog, _renames} = Migration.convert(catalog)

      for message <- catalog.messages do
        assert converted =~ inspect(IO.iodata_to_binary(message.msgid))
      end
    end

    test "converts calls in a HEEx template" do
      template =
        ~S|<p>{gettext("Hi %{name}", name: @n)}</p><%= dgettext("x", "Bye %{n}", n: 1) %>|

      assert Migration.convert_source(template) ==
               {:ok,
                ~S|<p>{gettext("Hi {$name}", name: @n)}</p><%= dgettext("x", "Bye {$n}", n: 1) %>|,
                %{rewritten: 2, skipped: []}}
    end

    test "leaves text with no call, an unclosed call and a non-Gettext call as they are" do
      for source <- [
            "",
            "no calls here",
            ~S|gettext("open %{x}"|,
            ~S|mygettext("x %{y}")|,
            ~S|@gettext("x %{y}")|
          ] do
        assert Migration.convert_source(source) == {:ok, source, %{rewritten: 0, skipped: []}},
               source
      end
    end

    test "makes no atom from the source" do
      name = "unseen_binding_#{System.unique_integer([:positive])}"

      assert {:ok, _source, %{rewritten: 1}} =
               Migration.convert_source("gettext(\"x %{y}\", #{name}: 1)")

      assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
    end

    test "returns an error for anything but a string" do
      for value <- [nil, 42, ~c"gettext"] do
        assert {:error, %Localize.InvalidValueError{}} = Migration.convert_source(value)
      end
    end
  end

  describe "plural entries" do
    @ru_forms ["%{count} день назад", "%{count} дня назад", "%{count} дней назад"]

    defp plural_catalog(language, plural_forms, forms) do
      msgstrs =
        forms
        |> Enum.with_index()
        |> Enum.map_join("\n", fn {form, index} -> ~s|msgstr[#{index}] "#{form}"| end)

      header =
        if is_nil(language) do
          ""
        else
          ~s|msgid ""\nmsgstr ""\n"Language: #{language}\\n"\n"Plural-Forms: #{plural_forms}\\n"\n\n|
        end

      Expo.PO.parse_string!(
        header <>
          ~s|msgid "%{count} day ago"\nmsgid_plural "%{count} days ago"\n| <> msgstrs <> "\n"
      )
    end

    defp converted_entry(catalog, options \\ [plurals: true]) do
      {:ok, converted, renames} = Migration.convert(catalog, options)
      [message] = converted.messages
      {message, renames}
    end

    defp gettext_choice(language, plural_forms, forms, count) do
      plural_info = Gettext.Plural.init(%{locale: language, plural_forms_header: plural_forms})

      Interpolation.runtime_interpolate(
        Enum.at(forms, Gettext.Plural.plural(plural_info, count)),
        %{count: count}
      )
    end

    test "becomes one .match message for the msgid and one for the msgstr" do
      catalog =
        plural_catalog(
          "ru",
          "nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);",
          @ru_forms
        )

      {message, renames} = converted_entry(catalog)

      assert %Expo.Message.Singular{} = message

      assert IO.iodata_to_binary(message.msgid) ==
               ".local $plural_count = {$count :number}\n.match $plural_count\none {{{$count} day ago}}\n* {{{$count} days ago}}"

      assert IO.iodata_to_binary(message.msgstr) ==
               ".local $plural_count = {$count :number}\n.match $plural_count\none {{{$count} день назад}}\nfew {{{$count} дня назад}}\n* {{{$count} дней назад}}"

      assert [
               %{
                 context: nil,
                 from: "%{count} day ago",
                 from_plural: "%{count} days ago",
                 to: _to
               }
             ] = renames
    end

    test "chooses the form Gettext chooses, for every count, in each language" do
      for {language, plural_forms, forms} <- [
            {"ru",
             "nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);",
             @ru_forms},
            {"fr", "nplurals=2; plural=(n != 1);", ["%{count} jour", "%{count} jours"]},
            {"fr", "nplurals=2; plural=(n > 1);", ["%{count} jour", "%{count} jours"]},
            {"pl",
             "nplurals=3; plural=(n==1 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);",
             ["%{count} dzień", "%{count} dni", "%{count} dni."]},
            {"ja", "nplurals=1; plural=0;", ["%{count}日前"]},
            {"ar",
             "nplurals=6; plural=(n==0 ? 0 : n==1 ? 1 : n==2 ? 2 : n%100>=3 && n%100<=10 ? 3 : n%100>=11 ? 4 : 5);",
             ~w(z o t f m x) |> Enum.map(&"%{count} #{&1}")}
          ] do
        {message, _renames} = converted_entry(plural_catalog(language, plural_forms, forms))
        {:ok, _locale} = Localize.put_locale(language)

        for count <- Enum.to_list(0..250) ++ [1000, 1001, 1011, 100_000, 1_000_000] do
          assert {language, count,
                  Interpolation.runtime_interpolate(IO.iodata_to_binary(message.msgstr), %{
                    count: count
                  })} ==
                   {language, count, gettext_choice(language, plural_forms, forms, count)}
        end
      end
    end

    test "takes an exact key for a count Gettext and CLDR place apart" do
      {message, _renames} =
        converted_entry(
          plural_catalog("fr", "nplurals=2; plural=(n != 1);", ["%{count} jour", "%{count} jours"])
        )

      assert IO.iodata_to_binary(message.msgstr) =~ "0 {{{$count} jours}}\none {{{$count} jour}}"
    end

    test "converts a template and an untranslated catalog" do
      {template, _renames} = converted_entry(plural_catalog(nil, nil, ["", ""]))
      assert IO.iodata_to_binary(template.msgstr) == ""

      assert IO.iodata_to_binary(template.msgid) =~
               ".match $plural_count\none {{{$count} day ago}}"

      {untranslated, _renames} =
        converted_entry(plural_catalog("de", "nplurals=2; plural=(n != 1);", ["", ""]))

      assert IO.iodata_to_binary(untranslated.msgstr) == ""
    end

    test "leaves an entry whose formula splits a CLDR category without end as a plural entry" do
      catalog =
        plural_catalog("en", "nplurals=2; plural=(n%10==1 ? 0 : 1);", [
          "%{count} day ago",
          "%{count} days ago"
        ])

      assert Migration.convertible_plurals(catalog) == {:ok, MapSet.new()}
      {message, renames} = converted_entry(catalog)

      assert %Expo.Message.Plural{} = message
      assert IO.iodata_to_binary(message.msgid) == "{$count} day ago"
      assert Enum.all?(renames, &(not Map.has_key?(&1, :from_plural)))
    end

    test "leaves an entry with a form that is not UTF-8 as a plural entry" do
      catalog =
        plural_catalog("fr", "nplurals=2; plural=(n > 1);", [
          <<"%{count} p", 0xE4, "ev">>,
          "%{count} jours"
        ])

      assert Migration.convertible_plurals(catalog) == {:ok, MapSet.new()}
      assert {%Expo.Message.Plural{}, _renames} = converted_entry(catalog)
    end

    test "converts only the entries a set of keys names, and none by default" do
      catalog =
        plural_catalog("fr", "nplurals=2; plural=(n > 1);", ["%{count} jour", "%{count} jours"])

      {:ok, keys} = Migration.convertible_plurals(catalog)

      assert {%Expo.Message.Singular{}, _renames} = converted_entry(catalog, plurals: keys)
      assert {%Expo.Message.Plural{}, _renames} = converted_entry(catalog, plurals: MapSet.new())
      assert {%Expo.Message.Plural{}, _renames} = converted_entry(catalog, [])
    end

    test "returns an error, never raises, for options it cannot use" do
      catalog =
        plural_catalog("fr", "nplurals=2; plural=(n > 1);", ["%{count} jour", "%{count} jours"])

      for options <- [
            [plurals: :yes],
            [plurals: true, source_locale: 42],
            [plurals: true, source_locale: "not a locale!"]
          ] do
        assert {:error, %{__exception__: true}} = Migration.convert(catalog, options),
               inspect(options)
      end

      assert {:error, %{__exception__: true}} = Migration.convertible_plurals(nil)
    end
  end

  describe "a message that is not UTF-8" do
    test "is returned unchanged by the interpolator, never raised on" do
      latin1 = <<"p", 0xE4, "ev %{count}">>

      log =
        capture_log(fn ->
          assert Interpolation.runtime_interpolate(latin1, %{count: 1}) == {:ok, latin1}
        end)

      assert log =~ "not valid MF2"
      assert Interpolation.mf2_source(latin1) == latin1
    end
  end
end
