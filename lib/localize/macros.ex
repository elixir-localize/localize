defmodule Localize.Macros do
  @moduledoc false

  @doc """
  Guard macro that checks if a value is `nil` or `false`.
  """
  defmacro is_false(value) do
    quote do
      is_nil(unquote(value)) or unquote(value) == false
    end
  end

  @doc """
  Sets `@impl true` for a callback implementation.
  """
  defmacro calendar_impl do
    quote do
      @impl true
    end
  end

  @doc """
  Logs a warning message only once per key per module.

  Uses `:persistent_term` to track whether the message
  has already been logged. Subsequent calls with the same
  key from the same module are silently ignored.
  """
  defmacro warn_once(key, message, level \\ :warning) do
    caller = __CALLER__.module

    quote do
      require Logger

      if Localize.Utils.Helpers.get_term({unquote(caller), unquote(key)}, true) do
        Logger.unquote(level)(unquote(message))
        Localize.Utils.Helpers.put_term({unquote(caller), unquote(key)}, nil)
      end
    end
  end
end
