defmodule Localize.Message.ParsedTest do
  use ExUnit.Case, async: true

  alias Localize.Message
  alias Localize.Message.Parsed

  @conformance_dir Path.expand("../../support/data/mf2_conformance", __DIR__)

  @conformance_files [
    "syntax.json",
    "data-model-errors.json",
    "pattern-selection.json",
    "fallback.json",
    "bidi.json",
    "u-options.json",
    "functions/currency.json",
    "functions/date.json",
    "functions/datetime.json",
    "functions/integer.json",
    "functions/number.json",
    "functions/offset.json",
    "functions/percent.json",
    "functions/string.json",
    "functions/time.json"
  ]

  @plural ".input {$count :number}\n.match $count\none {{One item}}\n* {{{$count} items}}"

  describe "parse/2" do
    test "parses and validates a message once" do
      assert {:ok, %Parsed{source: @plural, ast: [_ | _]}} = Message.parse(@plural)
    end

    test "trims the message with :trim" do
      assert {:ok, %Parsed{source: "{{Hi}}"}} = Message.parse("  {{Hi}}\n", trim: true)
      assert {:ok, %Parsed{source: "  {{Hi}}\n"}} = Message.parse("  {{Hi}}\n")
    end

    test "returns a ParseError for a message that is not valid MF2 syntax" do
      assert {:error, %Localize.ParseError{}} = Message.parse("bad {")
      assert {:error, %Localize.ParseError{}} = Message.parse(".match")
    end

    test "returns a FormatError for a message that breaks a data-model rule" do
      for {message, reason} <- [
            {".input {$n :number}\n.match $n\none {{One}}", :missing_fallback_variant},
            {".local $n = {$n :number}\n{{{$n}}}", :duplicate_declaration},
            {".match $n\n* {{x}}", :missing_selector_annotation}
          ] do
        assert {:error, %Localize.FormatError{reason: ^reason}} = Message.parse(message),
               inspect(message)
      end
    end

    test "returns an error, never raises, for arguments of the wrong type" do
      for {message, options} <- [
            {nil, []},
            {42, []},
            {~c"{{x}}", []},
            {"{{x}}", %{}},
            {"{{x}}", :trim}
          ] do
        assert {:error, %{__exception__: true}} = Message.parse(message, options),
               inspect({message, options})
      end
    end
  end

  describe "formatting a parsed message" do
    test "format/3 and format!/3 give the string's result" do
      {:ok, parsed} = Message.parse(@plural)

      for count <- [1, 3, 1_234], locale <- [:en, :de, :ar, :fa] do
        options = [locale: locale]

        assert Message.format(parsed, %{"count" => count}, options) ==
                 Message.format(@plural, %{"count" => count}, options)

        assert Message.format!(parsed, [count: count], options) ==
                 Message.format!(@plural, [count: count], options)
      end
    end

    test "format/3 gives the string's result on the ICU backend, or falls back to the interpreter" do
      {:ok, parsed} = Message.parse("{{Hello {$name}, you have {$n :number} messages}}")
      bindings = %{"name" => "Ana", "n" => 1_234}

      for bidi <- [:default, :none] do
        options = [backend: :nif, bidi: bidi, locale: :en]

        assert Message.format(parsed, bindings, options) ==
                 Message.format(parsed.source, bindings, options)
      end

      # A Decimal is not an ICU argument, so the interpreter formats it.
      decimal = %{"name" => "Ana", "n" => Decimal.new("12.5")}

      assert Message.format(parsed, decimal, backend: :nif, locale: :de) ==
               Message.format(parsed.source, decimal, backend: :nif, locale: :de)
    end

    test "format_to_iolist/3 and format_to_safe_list/3 give the string's result" do
      message = "{{Read {#link href=|/terms|}the terms{/link} for {$n :number} items}}"
      {:ok, parsed} = Message.parse(message)
      bindings = %{"n" => 2}

      assert Message.format_to_iolist(parsed, bindings) ==
               Message.format_to_iolist(message, bindings)

      assert Message.format_to_safe_list(parsed, bindings) ==
               Message.format_to_safe_list(message, bindings)

      assert Message.format_to_safe_list!(parsed, bindings) ==
               Message.format_to_safe_list!(message, bindings)
    end

    test "report unbound variables and bad arguments as for a string" do
      {:ok, parsed} = Message.parse("{{Hello {$name}}}")

      assert {:error, %Localize.BindError{unbound: ["name"]}} = Message.format(parsed, %{})
      assert {:error, %Localize.BindError{}} = Message.format(parsed, %{}, backend: :nif)
      assert {:error, %Localize.BindError{}} = Message.format_to_safe_list(parsed, %{})

      for {bindings, options} <- [
            {:bad, []},
            {%{}, :bad},
            {%{}, [output: :html]},
            {%{}, [locale: "not a locale!"]}
          ] do
        assert {:error, %{__exception__: true}} = Message.format(parsed, bindings, options),
               inspect({bindings, options})
      end

      assert {:error, %Localize.InvalidValueError{expected: expected}} =
               Message.format(parsed, :bad)

      assert expected =~ "bindings"
    end

    test "agrees with the string form on every MF2 working group formatting case" do
      results =
        for file <- @conformance_files,
            {source, params, options} <- conformance_cases(file),
            {:ok, parsed} <- [Message.parse(source)] do
          {source,
           Message.format(parsed, params, options) == Message.format(source, params, options)}
        end

      disagreements = for {source, false} <- results, do: source

      assert Enum.count_until(results, 301) > 300
      assert disagreements == []
    end

    test "fails to parse exactly where the string form fails to format with a parse or data-model error" do
      for file <- @conformance_files,
          {source, params, options} <- conformance_cases(file),
          {:error, parse_error} <- [Message.parse(source)] do
        assert {:error, format_error} = Message.format(source, params, options)
        assert format_error.__struct__ == parse_error.__struct__, source
      end
    end
  end

  defp conformance_cases(file) do
    data =
      @conformance_dir
      |> Path.join(file)
      |> File.read!()
      |> :json.decode()

    defaults = Map.get(data, "defaultTestProperties", %{})

    for test_case <- Map.fetch!(data, "tests") do
      source =
        case Map.fetch!(test_case, "src") do
          list when is_list(list) -> Enum.join(list)
          binary -> binary
        end

      bidi =
        if Map.get(test_case, "bidiIsolation", Map.get(defaults, "bidiIsolation", "none")) ==
             "default" do
          :default
        else
          :none
        end

      locale = Map.get(test_case, "locale", Map.get(defaults, "locale", "en-US"))
      params = Map.new(Map.get(test_case, "params", []), &param/1)

      {source, params, [locale: locale, bidi: bidi]}
    end
  end

  defp param(%{"name" => name, "value" => %{"date" => milliseconds}}) do
    {name, DateTime.from_unix!(milliseconds, :millisecond)}
  end

  defp param(%{"name" => name, "value" => %{"decimal" => string}}) do
    {name, Decimal.new(string)}
  end

  defp param(%{"name" => name, "value" => value}) do
    {name, value}
  end
end
