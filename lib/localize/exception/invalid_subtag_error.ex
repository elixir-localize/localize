defmodule Localize.InvalidSubtagError do
  @moduledoc """
  Exception raised when an extension key or value is not valid
  for a BCP 47 language tag.

  """

  defexception [:key, :value, :reason]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{key: key, value: value, reason: nil}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "language_tag",
      "The value {$value} is not valid for the key {$key}",
      value: inspect(value),
      key: inspect(key)
    )
  end

  def message(%__MODULE__{key: key, value: value, reason: reason}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "language_tag",
      "{$reason}",
      reason: reason,
      key: inspect(key),
      value: inspect(value)
    )
  end
end
