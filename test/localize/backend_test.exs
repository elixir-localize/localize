defmodule Localize.BackendTest do
  use ExUnit.Case, async: true

  alias Localize.Backend

  describe "resolve/1 with a keyword list" do
    test "returns :elixir when no backend is requested" do
      assert Backend.resolve([]) == :elixir
    end

    test "returns :elixir when :elixir is requested" do
      assert Backend.resolve(backend: :elixir) == :elixir
    end

    test "returns :elixir for an unrecognised backend" do
      assert Backend.resolve(backend: :fortran) == :elixir
    end

    test ":nif resolves to :nif only when the NIF is available" do
      expected = if Localize.Nif.available?(), do: :nif, else: :elixir
      assert Backend.resolve(backend: :nif) == expected
    end
  end

  describe "resolve/1 with a map" do
    test "returns :elixir when no backend is requested" do
      assert Backend.resolve(%{}) == :elixir
    end

    test "returns :elixir when :elixir is requested" do
      assert Backend.resolve(%{backend: :elixir}) == :elixir
    end

    test "returns :elixir for an unrecognised backend" do
      assert Backend.resolve(%{backend: "nif"}) == :elixir
    end

    test ":nif resolves to :nif only when the NIF is available" do
      expected = if Localize.Nif.available?(), do: :nif, else: :elixir
      assert Backend.resolve(%{backend: :nif}) == expected
    end
  end
end
