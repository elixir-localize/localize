defmodule Localize.CoreTextApiTest do
  @moduledoc """
  `Localize.ellipsis/2`, `Localize.quote/2` and the POSIX response functions
  against CLDR's `en` data: the ellipsis patterns "{0}…", "…{0}", "{0}…{1}",
  "{0} …", "… {0}" and "{0} … {1}", and the POSIX messages `yesstr` "yes:y"
  and `nostr` "no:n". Called without options each function uses the process
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

  describe "responses in the process locale" do
    test "negative_responses/0 returns the nostr forms" do
      assert Localize.negative_responses() == {:ok, ["no", "n"]}
    end

    test "affirmative?/1 and negative?/1 fold case and surrounding space" do
      assert Localize.affirmative?(" Yes ")
      assert Localize.negative?("N")
      refute Localize.affirmative?("no")
      refute Localize.negative?("yes")
    end
  end
end
