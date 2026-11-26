defmodule Localize.GrammaticalFeatureTest do
  # Not async: the atom-count test needs no other test making atoms meanwhile.
  use ExUnit.Case, async: false

  alias Localize.GrammaticalFeature

  describe "cast/2" do
    test "accepts every value of every feature as an atom and as its name" do
      for feature <- GrammaticalFeature.features(), value <- GrammaticalFeature.values(feature) do
        assert GrammaticalFeature.cast(feature, value) == {:ok, value}
        assert GrammaticalFeature.cast(feature, Atom.to_string(value)) == {:ok, value}
      end
    end

    test "takes CLDR's genders, animacy among them" do
      assert GrammaticalFeature.cast(:grammatical_gender, :animate) == {:ok, :animate}
      assert GrammaticalFeature.cast(:grammatical_gender, "personal") == {:ok, :personal}
      assert GrammaticalFeature.cast(:grammatical_gender, "common") == {:ok, :common}
    end

    test "nil is an option not given" do
      for feature <- GrammaticalFeature.features() do
        assert GrammaticalFeature.cast(feature, nil) == {:ok, nil}
      end
    end

    test "a value of another feature is an error" do
      assert {:error, %Localize.InvalidValueError{value: :genitive}} =
               GrammaticalFeature.cast(:grammatical_gender, :genitive)

      assert {:error, %Localize.InvalidValueError{value: "plural"}} =
               GrammaticalFeature.cast(:grammatical_case, "plural")
    end

    test "garbage is an error, never a crash" do
      long = String.duplicate("a", 10_000)

      for value <- [
            "",
            :"",
            "Genitive",
            " genitive",
            "genitive\u0000",
            long,
            :not_a_case,
            true,
            1,
            1.5,
            [],
            %{},
            {:genitive},
            ["genitive"],
            self()
          ] do
        assert {:error, %Localize.InvalidValueError{} = error} =
                 GrammaticalFeature.cast(:grammatical_case, value)

        assert error.expected == :grammatical_case
        assert error.allowed_values == GrammaticalFeature.values(:grammatical_case)
        assert is_binary(Exception.message(error))
      end
    end

    test "makes no atom from a string" do
      strings = for index <- 1..2_000, do: "grammatical-feature-test-#{index}"
      before = :erlang.system_info(:atom_count)

      for feature <- GrammaticalFeature.features(), string <- strings do
        assert {:error, _exception} = GrammaticalFeature.cast(feature, string)
      end

      assert :erlang.system_info(:atom_count) == before
    end
  end
end
