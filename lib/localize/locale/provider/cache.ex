defmodule Localize.Locale.Provider.Cache do
  @moduledoc """
  On-disk cache for downloaded locale data files.

  This module is responsible for reading and writing locale ETF
  files under the directory returned by
  `Localize.Locale.Provider.locale_cache_dir/0`, and for detecting
  when a cached file is stale relative to `Localize.version/0`.

  ## Primary API

  * `get/1` — returns cached locale data, or an error tuple if the
    file is missing or stale.

  * `store/2` — writes locale data to the cache directory.

  * `stale?/1` — checks whether a cached locale file is stale.

  * `path/1` — returns the absolute path for a locale's cache file.

  """

  alias Localize.Locale.Provider

  @typedoc "A locale identifier as an atom."
  @type locale_id :: atom()

  @doc """
  Returns the absolute cache file path for the given locale.

  ### Arguments

  * `locale_id` is a locale identifier atom.

  ### Returns

  * A string path to the locale's cache file.

  ### Examples

      iex> path = Localize.Locale.Provider.Cache.path(:en)
      iex> String.ends_with?(path, "en.etf")
      true

  """
  @spec path(locale_id()) :: String.t()
  def path(locale_id) when is_atom(locale_id) do
    Path.join(Provider.locale_cache_dir(), Provider.locale_file_name(locale_id))
  end

  @doc """
  Retrieves locale data from the cache directory.

  Reads the locale's cache file, decodes it, and validates that
  its `:version` field matches `Localize.version/0`.

  ### Arguments

  * `locale_id` is a locale identifier atom.

  ### Returns

  * `{:ok, locale_data}` if the cache file is present and its
    version matches the current version.

  * `{:error, Localize.LocaleIsStaleError.t()}` if the cache file
    is present but its version does not match.

  * `{:error, Localize.LocaleNotFoundInCacheError.t()}` if the
    cache file is not present.

  """
  @spec get(locale_id()) ::
          {:ok, map()} | {:error, Exception.t()}
  def get(locale_id) when is_atom(locale_id) do
    cache_dir = Provider.locale_cache_dir()
    bundled_dir = Provider.default_locale_cache_dir()
    file_name = Provider.locale_file_name(locale_id)

    search_paths =
      if cache_dir == bundled_dir do
        [Path.join(cache_dir, file_name)]
      else
        [Path.join(cache_dir, file_name), Path.join(bundled_dir, file_name)]
      end

    read_first(locale_id, search_paths)
  end

  defp read_first(locale_id, [file_path]) do
    read_and_validate(locale_id, file_path)
  end

  defp read_first(locale_id, [file_path | rest]) do
    case read_and_validate(locale_id, file_path) do
      {:ok, _locale_data} = success ->
        success

      # A stale file in an earlier search path is the more specific
      # diagnosis: the locale *is* cached, just at the wrong data
      # version. Keep it rather than reporting the last path's
      # "not found", which sends the reader looking for a missing file.
      {:error, %Localize.LocaleIsStaleError{}} = stale ->
        case read_first(locale_id, rest) do
          {:ok, _locale_data} = success -> success
          {:error, _later} -> stale
        end

      {:error, _reason} ->
        read_first(locale_id, rest)
    end
  end

  defp read_and_validate(locale_id, file_path) do
    case File.read(file_path) do
      {:ok, binary} ->
        case decode_etf(binary) do
          {:ok, locale_data} ->
            validate_version(locale_id, locale_data)

          {:error, :undecodable} ->
            # A corrupt or truncated cache file (torn write, disk
            # corruption) is a cache miss, not a crash — callers fall
            # back to download or the bundled data.
            {:error,
             Localize.LocaleNotFoundInCacheError.exception(
               locale_id: locale_id,
               path: file_path
             )}
        end

      {:error, :enoent} ->
        {:error,
         Localize.LocaleNotFoundInCacheError.exception(
           locale_id: locale_id,
           path: file_path
         )}

      {:error, reason} ->
        {:error,
         Localize.LocaleNotFoundInCacheError.exception(
           locale_id: locale_id,
           path: file_path,
           posix_error: reason
         )}
    end
  end

  # `binary_to_term/1` raises on anything that is not a complete,
  # well-formed external term — this is the only place pattern
  # matching cannot replace the raise, so the rescue is a true
  # system boundary around corrupt file content.
  defp decode_etf(binary) do
    {:ok, :erlang.binary_to_term(binary)}
  rescue
    ArgumentError -> {:error, :undecodable}
  end

  defp validate_version(locale_id, locale_data) do
    current_version = Localize.version()
    cached_version = Map.get(locale_data, :version)

    if versions_match?(cached_version, current_version) do
      {:ok, locale_data}
    else
      {:error,
       Localize.LocaleIsStaleError.exception(
         locale_id: locale_id,
         cached_version: cached_version,
         current_version: current_version
       )}
    end
  end

  @doc """
  Stores locale content in the cache directory.

  Creates the cache directory if it does not already exist and
  writes `content` to the locale's cache file. `content` should
  be the raw binary form of the locale ETF file.

  ### Arguments

  * `locale_id` is a locale identifier atom.

  * `content` is a binary containing the encoded locale data.

  ### Returns

  * `{:ok, path}` where `path` is the absolute path the content
    was written to.

  * `{:error, Localize.LocaleCacheWriteError.t()}` on failure.

  """
  @spec store(locale_id(), binary()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def store(locale_id, content) when is_atom(locale_id) and is_binary(content) do
    file_path = path(locale_id)
    dir = Path.dirname(file_path)

    # Write-then-rename so the cache file appears atomically. A crash
    # or SIGKILL mid-write, or two OS processes sharing a cache dir,
    # can otherwise leave a truncated `.etf` that later reads as
    # corrupt. `File.rename/2` within one directory is atomic on
    # POSIX filesystems. The temp name carries the writer's pid and a
    # unique suffix so concurrent writers never collide.
    temp_path =
      file_path <>
        ".tmp.#{System.pid()}.#{System.unique_integer([:positive])}"

    with :ok <- File.mkdir_p(dir),
         :ok <- File.write(temp_path, content),
         :ok <- rename_or_cleanup(temp_path, file_path) do
      {:ok, file_path}
    else
      {:error, reason} ->
        {:error,
         Localize.LocaleCacheWriteError.exception(
           locale_id: locale_id,
           path: file_path,
           posix_error: reason
         )}
    end
  end

  defp rename_or_cleanup(temp_path, file_path) do
    case File.rename(temp_path, file_path) do
      :ok ->
        :ok

      {:error, _reason} = error ->
        _ = File.rm(temp_path)
        error
    end
  end

  @doc """
  Returns whether a cached locale file is stale.

  A cache file is considered stale if its `:version` field does
  not equal `Localize.version/0`. A file that is missing,
  unreadable, or undecodable (corrupt) is also considered stale.

  ### Arguments

  * `locale_id` is a locale identifier atom.

  ### Returns

  * `true` if the cache file is missing, unreadable, or its
    version does not match `Localize.version/0`.

  * `false` if the cache file is present and its version matches.

  ### Examples

      iex> Localize.Locale.Provider.Cache.stale?(:"xx-NOPE")
      true

  """
  @spec stale?(locale_id()) :: boolean()
  def stale?(locale_id) when is_atom(locale_id) do
    file_path = path(locale_id)

    case File.read(file_path) do
      {:ok, binary} ->
        case decode_etf(binary) do
          {:ok, locale_data} ->
            not versions_match?(Map.get(locale_data, :version), Localize.version())

          # A corrupt cache file is stale by definition — it will be
          # re-downloaded and rewritten.
          {:error, :undecodable} ->
            true
        end

      {:error, _reason} ->
        true
    end
  end

  defp versions_match?(%Version{} = cached, %Version{} = current) do
    Version.compare(cached, current) == :eq
  end

  defp versions_match?(_cached, _current) do
    false
  end
end
