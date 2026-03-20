defmodule Localize.FormatError do
  @moduledoc """
  Exception raised when a value cannot be formatted by the requested
  message format function due to an incompatible type or missing
  configuration.

  """

  defexception [:value, :function, :reason]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{value: value, function: function, reason: reason})
      when not is_nil(reason) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "message",
      "Cannot format %{value} with function %{function}: %{reason}",
      value: inspect(value),
      function: inspect(function),
      reason: reason
    )
  end

  def message(%__MODULE__{value: value, function: function}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "message",
      "Cannot format %{value} with function %{function}",
      value: inspect(value),
      function: inspect(function)
    )
  end
end
