defmodule Localize.LocaleCacheWriteError do
  @moduledoc """
  Exception raised when a locale file cannot be written to the
  locale cache directory.

  """

  @behaviour Localize.Exception

  defexception [:locale_id, :path, :reason, :posix_error]

  @type reason ::
          :permission_denied
          | :no_such_directory
          | :disk_full
          | :read_only_filesystem
          | :file_exists
          | :other_io_error

  @type t :: %__MODULE__{
          locale_id: atom(),
          path: Path.t() | nil,
          reason: reason() | nil,
          posix_error: :file.posix() | term() | nil
        }

  @impl Localize.Exception
  def reason_atoms,
    do: [
      :permission_denied,
      :no_such_directory,
      :disk_full,
      :read_only_filesystem,
      :file_exists,
      :other_io_error
    ]

  @posix_to_reason %{
    eacces: :permission_denied,
    eperm: :permission_denied,
    enoent: :no_such_directory,
    enotdir: :no_such_directory,
    enospc: :disk_full,
    erofs: :read_only_filesystem,
    eexist: :file_exists
  }

  @impl true
  def exception(bindings) when is_list(bindings) do
    bindings = normalize_bindings(bindings)
    struct!(__MODULE__, bindings)
  end

  defp normalize_bindings(bindings) do
    case {Keyword.has_key?(bindings, :reason), Keyword.get(bindings, :posix_error)} do
      {false, posix} when is_atom(posix) and not is_nil(posix) ->
        Keyword.put(bindings, :reason, Map.get(@posix_to_reason, posix, :other_io_error))

      _ ->
        bindings
    end
  end

  @impl true
  def message(%__MODULE__{reason: :permission_denied, locale_id: locale_id, path: path}) do
    Localize.Exception.safe_message(
      "locale",
      "Cannot write locale {$locale_id} to {$path}: permission denied.",
      locale_id: inspect(locale_id),
      path: path
    )
  end

  def message(%__MODULE__{reason: :no_such_directory, locale_id: locale_id, path: path}) do
    Localize.Exception.safe_message(
      "locale",
      "Cannot write locale {$locale_id} to {$path}: parent directory does not exist.",
      locale_id: inspect(locale_id),
      path: path
    )
  end

  def message(%__MODULE__{reason: :disk_full, locale_id: locale_id, path: path}) do
    Localize.Exception.safe_message(
      "locale",
      "Cannot write locale {$locale_id} to {$path}: no space left on device.",
      locale_id: inspect(locale_id),
      path: path
    )
  end

  def message(%__MODULE__{reason: :read_only_filesystem, locale_id: locale_id, path: path}) do
    Localize.Exception.safe_message(
      "locale",
      "Cannot write locale {$locale_id} to {$path}: filesystem is read-only.",
      locale_id: inspect(locale_id),
      path: path
    )
  end

  def message(%__MODULE__{reason: :file_exists, locale_id: locale_id, path: path}) do
    Localize.Exception.safe_message(
      "locale",
      "Cannot write locale {$locale_id} to {$path}: file already exists.",
      locale_id: inspect(locale_id),
      path: path
    )
  end

  def message(%__MODULE__{
        reason: :other_io_error,
        locale_id: locale_id,
        path: path,
        posix_error: posix
      }) do
    Localize.Exception.safe_message(
      "locale",
      "Cannot write locale {$locale_id} to {$path}: {$reason}.",
      locale_id: inspect(locale_id),
      path: path,
      reason: inspect(posix)
    )
  end

  def message(%__MODULE__{locale_id: locale_id, path: path, posix_error: posix}) do
    Localize.Exception.safe_message(
      "locale",
      "Cannot write locale {$locale_id} to {$path}: {$reason}.",
      locale_id: inspect(locale_id),
      path: path,
      reason: inspect(posix)
    )
  end
end
