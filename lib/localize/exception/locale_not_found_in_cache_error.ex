defmodule Localize.LocaleNotFoundInCacheError do
  @moduledoc """
  Exception raised when a locale file is not found in the locale
  cache directory.

  """

  defexception [:locale_id, :path]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{locale_id: locale_id, path: path}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "locale",
      "The locale {$locale_id} was not found in the cache at {$path}. " <>
        "Run `mix localize.download_locales {$locale_id_bare}` to download it, " <>
        "or set `config :localize, :allow_runtime_locale_download, true` to " <>
        "enable on-demand downloading.",
      locale_id: inspect(locale_id),
      locale_id_bare: locale_id,
      path: inspect(path)
    )
  end
end
