if Code.ensure_loaded?(Localize.Number) do
  defmodule Localize.Message.MultiValueMatchingTest do
    use ExUnit.Case, async: true

    alias Localize.Message.{Interpreter, Parser}

    defp format(source, bindings) do
      {:ok, parsed} = Parser.parse(source)
      options = [locale: "en-US"]

      case Interpreter.format_list(parsed, bindings, options) do
        {:ok, iolist, _, _} -> :erlang.iolist_to_binary(iolist)
        {:error, iolist, _, _} -> :erlang.iolist_to_binary(iolist)
      end
    end

    describe "multi-value selections" do
      test "with 2 selectors" do
        message = """
        .input {$pronoun :string}
        .input {$count :number}
        .match $pronoun $count
          he one   {{He has {$count} notification.}}
          he *     {{He has {$count} notifications.}}
          she one  {{She has {$count} notification.}}
          she *    {{She has {$count} notifications.}}
          * one    {{They have {$count} notification.}}
          * *      {{They have {$count} notifications.}}
        """

        assert "He has 3 notifications." = format(message, %{pronoun: "he", count: 3})
        assert "She has 1 notification." = format(message, %{pronoun: "she", count: 1})
        assert "They have 1 notification." = format(message, %{pronoun: "?", count: 1})
      end
    end
  end
end
