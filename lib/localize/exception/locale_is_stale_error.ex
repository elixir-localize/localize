defmodule Localize.LocaleIsStaleError do
  @moduledoc """
  Exception raised when a cached locale file's version does not
  match the current `Localize.version/0`.

  """

  defexception [:locale_id, :cached_version, :current_version]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{
        locale_id: locale_id,
        cached_version: cached_version,
        current_version: current_version
      }) do
    Localize.Exception.safe_message(
      "locale",
      "The cached locale {$locale_id} has CLDR data version {$cached_version} " <>
        "but this release of Localize requires {$current_version}. " <>
        "Run `mix localize.download_locales {$locale_id_bare}` to refresh it, " <>
        "or set `config :localize, :allow_runtime_locale_download, true` to " <>
        "enable on-demand downloading.",
      locale_id: inspect(locale_id),
      locale_id_bare: locale_id,
      cached_version: version_string(cached_version),
      current_version: version_string(current_version)
    )
  end

  defp version_string(%Version{} = version), do: Version.to_string(version)
  defp version_string(other), do: inspect(other)
end
