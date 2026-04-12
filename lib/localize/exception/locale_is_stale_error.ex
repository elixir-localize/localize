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
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "locale",
      "The cached locale {$locale_id} has version {$cached_version} but the current version is {$current_version}.",
      locale_id: inspect(locale_id),
      cached_version: inspect(cached_version),
      current_version: inspect(current_version)
    )
  end
end
