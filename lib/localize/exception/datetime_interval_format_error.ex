defmodule Localize.DateTimeIntervalFormatError do
  @moduledoc """
  Exception raised when an interval format cannot be resolved.

  """

  defexception [:reason, :fields, :format, :format_key, :detail]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{reason: :unknown_fields, fields: fields, format: format}) do
    Localize.Exception.safe_message(
      "datetime",
      "Unknown interval fields {$fields} or format {$format}.",
      fields: inspect(fields),
      format: inspect(format)
    )
  end

  def message(%__MODULE__{reason: :no_format, format_key: format_key}) do
    Localize.Exception.safe_message(
      "datetime",
      "No interval format found for {$format_key}.",
      format_key: inspect(format_key)
    )
  end

  def message(%__MODULE__{reason: :no_pattern, format_key: format_key, detail: detail}) do
    Localize.Exception.safe_message(
      "datetime",
      "No interval pattern for difference {$detail} in format {$format_key}.",
      detail: inspect(detail),
      format_key: inspect(format_key)
    )
  end

  def message(%__MODULE__{reason: :invalid_format, detail: detail}) do
    Localize.Exception.safe_message(
      "datetime",
      "Invalid interval format {$detail}.",
      detail: inspect(detail)
    )
  end

  def message(%__MODULE__{reason: :unterminated_quote}) do
    Localize.Exception.safe_message(
      "datetime",
      "Unterminated quote in interval format."
    )
  end

  def message(%__MODULE__{reason: :no_fallback}) do
    Localize.Exception.safe_message(
      "datetime",
      "No interval format fallback pattern available in the locale data."
    )
  end

  def message(%__MODULE__{reason: :mixed_endpoints, detail: detail}) do
    Localize.Exception.safe_message(
      "datetime",
      "Interval endpoints must be the same kind of value. Found {$detail}.",
      detail: detail
    )
  end
end
