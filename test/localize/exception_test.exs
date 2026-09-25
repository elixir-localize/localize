defmodule Localize.ExceptionTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  describe "safe_message/3 message degradation" do
    test "an invalid MF2 msgid degrades to the raw msgid" do
      # "Unclosed {" is not parseable MF2; the interpolation layer
      # logs the parse failure and safe_message returns the msgid
      # unchanged instead of raising.
      {result, log} =
        with_log(fn ->
          Localize.Exception.safe_message("number", "Unclosed {", [])
        end)

      assert result == "Unclosed {"
      assert log =~ "not valid MF2"
    end

    test "a plain message without placeholders is returned as-is" do
      assert Localize.Exception.safe_message("number", "Plain message") == "Plain message"
    end

    test "bindings are interpolated into the message" do
      assert Localize.Exception.safe_message(
               "number",
               "Could not parse {$input}",
               input: "abc"
             ) == "Could not parse abc"
    end
  end

  describe "messages carry their bindings" do
    test "a missing dependency names the package and the operation" do
      message =
        Exception.message(
          Localize.DependencyRequiredError.exception(
            package: "calendrical",
            operation: "parsing a date in the :japanese calendar"
          )
        )

      assert message =~ "calendrical"
      assert message =~ "parsing a date in the :japanese calendar"
    end
  end
end
