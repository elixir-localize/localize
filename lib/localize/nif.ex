defmodule Localize.Nif do
  @moduledoc """
  Optional NIF interface to ICU4C for high-performance locale operations.

  This module provides the NIF lifecycle management and availability
  checking. NIF functions for units, numbers, dates, and other
  locale-aware operations will be added here as the library grows.

  The NIF is opt-in and requires:

  1. ICU system libraries installed (`libicu` or `icucore` on macOS).

  2. The `elixir_make` dependency.

  3. Enable the NIF via either:
     * Environment variable: `LOCALIZE_NIF=true mix compile`
     * Application config in `config.exs`: `config :localize, :nif, true`

  The config key must be set in `config.exs` (not `runtime.exs`) because
  it is evaluated at compile time to include the `:elixir_make` compiler.

  If the NIF is not available, `available?/0` returns `false` and the
  pure Elixir implementations are used automatically.

  """

  @on_load :init

  @doc false
  def init do
    path = :code.priv_dir(:localize) ++ ~c"/localize_nif"

    case :erlang.load_nif(path, 0) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end

  @doc """
  Returns whether the NIF backend is available.

  ### Returns

  * `true` if the NIF shared library was loaded successfully.

  * `false` if the NIF is not compiled or ICU libraries are missing.

  ### Examples

      iex> is_boolean(Localize.Nif.available?())
      true

  """
  @spec available?() :: boolean()
  def available? do
    nif_loaded?()
  end

  defp nif_loaded? do
    # The NIF is loaded if :erlang.load_nif/2 succeeded during @on_load.
    # We check by verifying that the module's NIF flag is set.
    # Since we have no NIF functions yet, we probe by attempting to
    # re-load and checking the error reason.
    path = :code.priv_dir(:localize) ++ ~c"/localize_nif"

    case :erlang.load_nif(path, 0) do
      {:error, {:reload, _}} -> true
      {:error, {:upgrade, _}} -> true
      _ -> false
    end
  end
end
