defmodule Localize.LocaleDownloadError do
  @moduledoc """
  Exception raised when a locale file cannot be downloaded from
  its remote URL.

  """

  defexception [:locale_id, :url, :reason]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{locale_id: locale_id, url: url, reason: reason}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "locale",
      "The locale %{locale_id} could not be downloaded from %{url}: %{reason}.",
      locale_id: inspect(locale_id),
      url: inspect(url),
      reason: to_string(reason)
    )
  end
end
