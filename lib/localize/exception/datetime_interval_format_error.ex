defmodule Localize.DateTimeIntervalFormatError do
  @moduledoc """
  Exception raised when an interval format cannot be resolved.

  """

  defexception [:reason, :style, :format, :format_key, :detail]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{reason: :unknown_style, style: style, format: format}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "datetime",
      "Unknown interval style {$style} or format {$format}.",
      style: inspect(style),
      format: inspect(format)
    )
  end

  def message(%__MODULE__{reason: :no_format, format_key: format_key}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "datetime",
      "No interval format found for {$format_key}.",
      format_key: inspect(format_key)
    )
  end

  def message(%__MODULE__{reason: :no_pattern, format_key: format_key, detail: detail}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "datetime",
      "No interval pattern for difference {$detail} in format {$format_key}.",
      detail: inspect(detail),
      format_key: inspect(format_key)
    )
  end

  def message(%__MODULE__{reason: :invalid_format, detail: detail}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "datetime",
      "Invalid interval format {$detail}.",
      detail: inspect(detail)
    )
  end

  def message(%__MODULE__{reason: :unterminated_quote}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "datetime",
      "Unterminated quote in interval format."
    )
  end

  def message(%__MODULE__{reason: :no_fallback}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "datetime",
      "No interval format fallback pattern available in the locale data."
    )
  end
end
