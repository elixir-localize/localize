defmodule Localize.CoreTextApiTest do
  @moduledoc """
  `Localize.ellipsis/2` and `Localize.quote/2` against CLDR's `en` data: the
  ellipsis patterns "{0}…", "…{0}", "{0}…{1}", "{0} …", "… {0}" and
  "{0} … {1}". Called without options each function uses the process
  locale, `:en` in the test suite.

  """

  use ExUnit.Case, async: true

  describe "ellipsis/2 in the word format" do
    test "between two strings" do
      assert Localize.ellipsis(["start", "end"], format: :word) == {:ok, "start … end"}
    end

    test "before a string" do
      assert Localize.ellipsis("text", location: :before, format: :word) == {:ok, "… text"}
    end
  end

  test "quote/2 with an unknown format is an error" do
    assert {:error, %Localize.InvalidValueError{value: :bogus}} =
             Localize.quote("text", format: :bogus)
  end
end
