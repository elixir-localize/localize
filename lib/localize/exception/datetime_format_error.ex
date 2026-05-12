defmodule Localize.DateTimeFormatError do
  @moduledoc """
  Exception raised when a date, time, or datetime format
  pattern cannot be processed.

  """

  defexception [:format, :reason, :detail]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{format: format, reason: :invalid_format}) do
    Localize.Exception.safe_message(
      "datetime",
      "The format {$format} is invalid.",
      format: inspect(format)
    )
  end

  def message(%__MODULE__{format: format, reason: :tokenize_error, detail: detail}) do
    Localize.Exception.safe_message(
      "datetime",
      "Could not tokenize the format {$format}: {$detail}.",
      format: inspect(format),
      detail: inspect(detail)
    )
  end

  def message(%__MODULE__{format: format, reason: reason}) when not is_nil(reason) do
    Localize.Exception.safe_message(
      "datetime",
      "The format {$format} is invalid: {$reason}.",
      format: inspect(format),
      reason: inspect(reason)
    )
  end

  def message(%__MODULE__{format: format}) do
    Localize.Exception.safe_message(
      "datetime",
      "The format {$format} is invalid.",
      format: inspect(format)
    )
  end
end
