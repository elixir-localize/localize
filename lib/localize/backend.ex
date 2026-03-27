defmodule Localize.Backend do
  @moduledoc false

  # Resolves the `:backend` option to either `:nif` or `:elixir`.
  #
  # Rules:
  # * If `:backend` is `:nif` and the NIF is available, returns `:nif`.
  # * If `:backend` is `:nif` and the NIF is NOT available, returns `:elixir`.
  # * If `:backend` is `:elixir`, returns `:elixir`.
  # * If `:backend` is anything else or not set, returns `:elixir`.

  @spec resolve(Keyword.t()) :: :nif | :elixir
  def resolve(options) when is_list(options) do
    case Keyword.get(options, :backend) do
      :nif -> if nif_available?(), do: :nif, else: :elixir
      _ -> :elixir
    end
  end

  @spec resolve(map()) :: :nif | :elixir
  def resolve(options) when is_map(options) do
    case Map.get(options, :backend) do
      :nif -> if nif_available?(), do: :nif, else: :elixir
      _ -> :elixir
    end
  end

  defp nif_available? do
    Localize.Nif.available?()
  end
end
