defmodule Localize.InflectionDataNotAvailableError do
  @moduledoc """
  Exception returned when a language is supported by the Unicode
  inflection data but the data has not been downloaded.

  """

  defexception [:locale]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{locale: locale}) do
    Localize.Exception.safe_message(
      "inflection",
      "Inflection data for locale {$locale} has not been downloaded. Run mix localize.inflection.download or configure :inflection_data_dir.",
      locale: inspect(locale)
    )
  end
end
