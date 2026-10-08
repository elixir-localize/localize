defmodule Localize.DateTimeUnresolvedFormatError do
  @moduledoc """
  Exception raised when a date, time, or datetime format
  skeleton cannot be resolved to a pattern for the given locale.

  """

  defexception [:format, :locale]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, Localize.Exception.normalize_locale_bindings(bindings))
  end

  @impl true
  def message(%__MODULE__{format: format, locale: locale}) do
    Localize.Exception.safe_message(
      "datetime",
      "No available format resolved for {$format} in locale {$locale}.",
      format: inspect(format),
      locale: Localize.Exception.locale_name(locale)
    )
  end
end
