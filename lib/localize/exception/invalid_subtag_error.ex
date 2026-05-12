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
  def message(%__MODULE__{reason: :date_not_last, key: key, value: value}) do
    Localize.Exception.safe_message(
      "language_tag",
      "The date {$value} must be the last value in subtag {$key}.",
      value: inspect(value),
      key: inspect(key)
    )
  end

  def message(%__MODULE__{reason: :unknown_script, value: value}) do
    Localize.Exception.safe_message(
      "language_tag",
      "No unicode script {$value} found.",
      value: inspect(value)
    )
  end

  def message(%__MODULE__{reason: :invalid_key, key: key}) do
    Localize.Exception.safe_message(
      "language_tag",
      "The key {$key} is not valid for the -u- subtag.",
      key: inspect(key)
    )
  end

  def message(%__MODULE__{key: key, value: value}) do
    Localize.Exception.safe_message(
      "language_tag",
      "The value {$value} is not valid for the key {$key}.",
      value: inspect(value),
      key: inspect(key)
    )
  end
end
