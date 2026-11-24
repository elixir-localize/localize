defmodule Localize.Message.BidiTest do
  # TR35's Default Bidi Strategy, the default for a message formatted as a
  # single string, with value directionality as ICU 79 resolves it.
  use ExUnit.Case, async: true

  alias Localize.Message

  @lri "\u2066"
  @rli "\u2067"
  @fsi "\u2068"
  @pdi "\u2069"

  defp format(message, bindings, options) do
    {:ok, formatted} = Message.format(message, bindings, options)
    formatted
  end

  describe "the Default Bidi Strategy" do
    test "a value of unknown direction is isolated with FSI in any message" do
      for locale <- [:en, :ar] do
        assert format("{{a {$x}}}", %{"x" => "b"}, locale: locale) == "a #{@fsi}b#{@pdi}"
        assert format("{{a {$x :string}}}", %{"x" => "b"}, locale: locale) == "a #{@fsi}b#{@pdi}"
        assert format("{{a {|b|}}}", %{}, locale: locale) == "a #{@fsi}b#{@pdi}"
      end
    end

    test "a number or date has the locale's direction" do
      assert format("{{a {$n :number}}}", %{"n" => 3}, locale: :en) == "a 3"

      assert format("{{a {$n :number}}}", %{"n" => 3}, locale: :ar) ==
               "a #{@rli}#{format("{$n :number}", %{"n" => 3}, locale: :ar, bidi: :none)}#{@pdi}"

      assert format("{{a {$d :date}}}", %{"d" => ~D[2026-11-17]}, locale: :en) ==
               "a " <> format("{$d :date}", %{"d" => ~D[2026-11-17]}, locale: :en, bidi: :none)
    end

    test "the locale's direction is its script's, as CLDR records it" do
      # Tifinagh (`zgh`) is written left to right and Hanifi Rohingya
      # (`rhg`) right to left.
      assert format("{{a {$n :number}}}", %{"n" => 3}, locale: "zgh") ==
               "a " <> format("{$n :number}", %{"n" => 3}, locale: "zgh", bidi: :none)

      assert format("{{a {$n :number}}}", %{"n" => 3}, locale: "rhg") ==
               "a #{@rli}#{format("{$n :number}", %{"n" => 3}, locale: "rhg", bidi: :none)}#{@pdi}"
    end

    test "a bare variable takes the direction of its declaration" do
      assert format(".input {$n :number} {{a {$n}}}", %{"n" => 3}, locale: :en) == "a 3"
      assert format(".local $s = {|b|} {{a {$s}}}", %{}, locale: :en) == "a #{@fsi}b#{@pdi}"
    end

    test "markup and text are never isolated" do
      assert format("{{a {#b}c{/b}}}", %{}, locale: :en) == "a c"
    end
  end

  describe "u:dir" do
    test "ltr, rtl and auto isolate; inherit does not" do
      assert format("{{a {$n :number u:dir=ltr}}}", %{"n" => 3}, locale: :en) ==
               "a #{@lri}3#{@pdi}"

      assert format("{{a {$n :number u:dir=rtl}}}", %{"n" => 3}, locale: :en) ==
               "a #{@rli}3#{@pdi}"

      assert format("{{a {$n :number u:dir=auto}}}", %{"n" => 3}, locale: :en) ==
               "a #{@lri}3#{@pdi}"

      assert format("{{a {$n :number u:dir=inherit}}}", %{"n" => 3}, locale: :en) == "a 3"
    end

    test "auto on a value of unknown direction is FSI" do
      assert format("{{a {$x :string u:dir=auto}}}", %{"x" => "b"}, locale: :en) ==
               "a #{@fsi}b#{@pdi}"
    end

    test "set by a variable" do
      assert format("{{a {$x :string u:dir=$d}}}", %{"x" => "b", "d" => "rtl"}, locale: :en) ==
               "a #{@rli}b#{@pdi}"
    end

    test "kept by a declaration's resolved value" do
      assert format(".local $x = {|b| :string u:dir=ltr} {{a {$x}}}", %{}, locale: :en) ==
               "a #{@lri}b#{@pdi}"
    end

    test "a value TR35 does not define is ignored" do
      assert format("{{a {$n :number u:dir=sideways}}}", %{"n" => 3}, locale: :en) == "a 3"
    end

    test "on markup is a Bad Option error" do
      assert {:error, %Localize.FormatError{}} = Message.format("{#b u:dir=rtl}c{/b}", %{})
    end
  end

  describe "where the strategy applies" do
    test "bidi: :none isolates nothing" do
      assert format("{{a {$x}}}", %{"x" => "b"}, locale: :en, bidi: :none) == "a b"

      # Even with `u:dir`, as in ICU.
      assert format("{{a {$n :number u:dir=rtl}}}", %{"n" => 3}, locale: :en, bidi: :none) ==
               "a 3"
    end

    test "structured output isolates nothing unless asked" do
      assert {:ok, [{:text, "a b"}]} = Message.format_to_safe_list("{{a {$x}}}", %{"x" => "b"})
    end

    test "SSML output isolates nothing" do
      assert format("{{a {$x}}}", %{"x" => "b"}, locale: :en, output: :ssml) == "a b"
    end

    test "Localize's own messages carry no isolates" do
      {:error, error} = Localize.Message.Parser.parse("Hello\n{")
      refute Exception.message(error) =~ ~r/[\x{2066}-\x{2069}]/u
    end

    test "an invalid bidi option on the raw NIF function is an error" do
      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Nif.mf2_format("{$x}", "en", %{"x" => "b"}, bidi: :sideways)
    end
  end

  describe "the NIF backend" do
    @tag :nif
    test "gives the interpreter's output, isolated or not" do
      if Localize.Nif.available?() do
        messages = [
          {"{{a {$x}}}", %{"x" => "b"}},
          {"{{a {$n :number}}}", %{"n" => 3}},
          {"{{a {|b|}}}", %{}},
          {"{{a {$x :string u:dir=rtl}}}", %{"x" => "b"}}
        ]

        for {message, bindings} <- messages, locale <- [:en, :ar], bidi <- [:default, :none] do
          options = [locale: locale, bidi: bidi]

          assert Message.format(message, bindings, [{:backend, :nif} | options]) ==
                   Message.format(message, bindings, [{:backend, :elixir} | options]),
                 "#{message} #{inspect(options)}"
        end
      end
    end
  end
end
