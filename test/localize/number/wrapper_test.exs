defmodule Localize.Number.WrapperTest do
  use ExUnit.Case, async: true

  defp wrapper(string, tag) do
    "<#{tag}>#{string}<#{tag}>"
  end

  describe "wrapper function" do
    test "wrapping a number" do
      assert {:ok, "<number>100<number>"} =
               Localize.Number.to_string(100, wrapper: &wrapper/2)
    end

    test "wrapping a percent" do
      assert {:ok, "<number>10,000<number><percent>%<percent>"} =
               Localize.Number.to_string(100, format: :percent, wrapper: &wrapper/2)
    end

    test "wrapping plus and minus" do
      assert {:ok, "<plus>+<plus><number>100<number>"} =
               Localize.Number.to_string(100, format: "+##", wrapper: &wrapper/2)

      assert {:ok, "<minus>-<minus><number>100<number>"} =
               Localize.Number.to_string(-100, format: "##", wrapper: &wrapper/2)
    end

    test "wrapping a literal" do
      assert {:ok, "<literal>some string <literal><number>100<number>"} =
               Localize.Number.to_string(100,
                 format: "some string ##",
                 wrapper: &wrapper/2
               )
    end
  end
end
