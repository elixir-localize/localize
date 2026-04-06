defmodule Localize.LocaleCacheWriteError do
  @moduledoc """
  Exception raised when a locale file cannot be written to the
  locale cache directory.

  """

  defexception [:locale_id, :path, :reason]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{locale_id: locale_id, path: path, reason: reason}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "locale",
      "The locale %{locale_id} could not be written to the cache at %{path}: %{reason}.",
      locale_id: inspect(locale_id),
      path: inspect(path),
      reason: to_string(reason)
    )
  end
end
