defmodule Localize.LocaleNotFoundInCacheError do
  @moduledoc """
  Exception raised when a locale file is not found in the locale
  cache directory, or cannot be read for another I/O reason.

  """

  defexception [:locale_id, :path, :posix_error]

  @type t :: %__MODULE__{
          locale_id: atom(),
          path: Path.t() | nil,
          posix_error: :file.posix() | term() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{locale_id: locale_id, path: path, posix_error: nil}) do
    Localize.Exception.safe_message(
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

  def message(%__MODULE__{locale_id: locale_id, path: path, posix_error: posix}) do
    Localize.Exception.safe_message(
      "locale",
      "The locale {$locale_id} could not be read from the cache at {$path}: {$reason}.",
      locale_id: inspect(locale_id),
      path: inspect(path),
      reason: inspect(posix)
    )
  end
end
