defmodule Localize.Inflection.Provider do
  @moduledoc """
  Downloads inflection data files from the Localize CDN.

  Inflection data is optional and versioned independently of both
  the Localize package and the CLDR data: its version is the
  pinned unicode-org/inflection commit (abbreviated) plus a
  pipeline revision, so the data only re-publishes when the
  upstream pin or the generation pipeline changes.

  Files live at `<base-url>/<data-version>/<file>` — one
  `<locale>.etf` per locale plus a single `pronouns.etf` pack of
  all pronoun tables. Downloads are verified against the SHA-256
  manifest shipped in the package (`priv/localize/inflection_hashes.etf`)
  before anything is written, mirroring the locale-file integrity
  scheme (see `Localize.Locale.Provider`).

  """

  alias Localize.Inflection.DataDir

  # The pinned unicode-org/inflection commit the data is built from
  # lives in priv/localize/localize_inflection_sha, mirroring the
  # CLDR release in priv/localize/version. Recording it in a data
  # file gives the pin a single source of truth that the CI upload
  # workflow reads without compiling Elixir.
  @external_resource Application.app_dir(:localize, "priv/localize/localize_inflection_sha")

  @upstream_sha :localize
                |> Application.app_dir("priv/localize/localize_inflection_sha")
                |> File.read!()
                |> String.trim()

  # The pipeline revision. Bump it when the generation pipeline
  # changes the artifacts without an upstream commit bump; the CDN
  # path carries both the sha and the revision so objects stay
  # immutable.
  @data_revision 1

  @default_base_url "https://elixir-localize.com/inflection"
  @manifest "inflection_hashes.etf"
  @manifest_key {:localize, :inflection_hashes}

  @doc """
  Returns the full pinned unicode-org/inflection commit SHA.

  """
  def upstream_sha, do: @upstream_sha

  @doc """
  Returns the inflection data version.

  ### Examples

      iex> Localize.Inflection.Provider.data_version()
      "2333a964e53a-r1"

  """
  def data_version do
    binary_part(@upstream_sha, 0, 12) <> "-r#{@data_revision}"
  end

  @doc """
  Returns the CDN base URL for inflection data.

  Overridable for mirrors:

      config :localize, inflection_base_url: "https://mirror.example.com/inflection"

  """
  def base_url do
    Application.get_env(:localize, :inflection_base_url, @default_base_url)
  end

  @doc """
  Returns the download URL for a data file of the current data
  version.

  ### Examples

      iex> Localize.Inflection.Provider.file_url("ru.etf")
      "https://elixir-localize.com/inflection/2333a964e53a-r1/ru.etf"

  """
  def file_url(file_name) do
    base_url() <> "/" <> data_version() <> "/" <> file_name
  end

  @doc """
  Downloads a data file and verifies it against the packaged
  SHA-256 manifest.

  ### Arguments

  * `file_name` is a file name such as "ru.etf" or "pronouns.etf".

  ### Returns

  * `{:ok, binary}` with the verified contents, or
    `{:error, exception}`.

  """
  def download_file(file_name) do
    url = file_url(file_name)

    case Localize.Utils.Http.get(url) do
      {:ok, body} when is_binary(body) ->
        verify(file_name, url, body)

      {:error, reason} ->
        {:error, download_error(reason, file_name, url)}

      other ->
        {:error, download_error(other, file_name, url)}
    end
  end

  # `Localize.Utils.Http.get/1` reports transport failures as bare
  # terms (e.g. an HTTP status integer like `404`). Localize's error
  # convention is `{:error, exception}`, so any non-exception reason
  # is wrapped in a `LocaleDownloadError`; an already-formed exception
  # (for example from `verify/3`) passes through unchanged. Returning
  # a bare term here previously crashed callers that called
  # `Exception.message/1` on it.
  defp download_error(%{__exception__: true} = exception, _file_name, _url), do: exception

  defp download_error(reason, file_name, url) do
    Localize.LocaleDownloadError.exception(locale_id: file_name, url: url, cause: reason)
  end

  # Verification runs before any cache write, so the data
  # directory only ever contains verified content. A missing
  # manifest (source builds before hashes are generated) logs a
  # one-time warning and skips verification, as the locale
  # provider does.
  defp verify(file_name, url, body) do
    case manifest_hash(file_name) do
      :no_manifest ->
        warn_missing_manifest()
        {:ok, body}

      nil ->
        {:error,
         Localize.LocaleIntegrityError.exception(
           locale_id: file_name,
           url: url,
           reason: :no_manifest_entry
         )}

      expected ->
        if :crypto.hash(:sha256, body) == expected do
          {:ok, body}
        else
          {:error,
           Localize.LocaleIntegrityError.exception(
             locale_id: file_name,
             url: url,
             reason: :hash_mismatch
           )}
        end
    end
  end

  defp manifest_hash(file_name) do
    case manifest() do
      :no_manifest -> :no_manifest
      hashes -> Map.get(hashes, file_name)
    end
  end

  defp manifest do
    case :persistent_term.get(@manifest_key, :not_loaded) do
      :not_loaded ->
        loaded = load_manifest()
        :persistent_term.put(@manifest_key, loaded)
        loaded

      loaded ->
        loaded
    end
  end

  defp load_manifest do
    path = Application.app_dir(:localize, Path.join("priv/localize", @manifest))

    case File.read(path) do
      {:ok, binary} -> :erlang.binary_to_term(binary)
      {:error, _reason} -> :no_manifest
    end
  end

  defp warn_missing_manifest do
    case :persistent_term.get({:localize, :inflection_hashes_warned}, false) do
      false ->
        require Logger

        Logger.warning(
          "No inflection hash manifest found; downloaded inflection data will not be integrity-checked. " <>
            "Run mix localize.inflection.generate_hashes and rebuild."
        )

        :persistent_term.put({:localize, :inflection_hashes_warned}, true)

      true ->
        :ok
    end
  end

  @doc """
  Writes the pronoun tables pack into the data directory as the
  individual CSV files the runtime reads.

  ### Arguments

  * `pack` is the decoded `pronouns.etf` map of file name to
    contents.

  ### Returns

  * `:ok` after writing all tables.

  """
  def unpack_pronouns(pack) when is_map(pack) do
    File.mkdir_p!(DataDir.dir())

    Enum.each(pack, fn {file_name, contents} ->
      File.write!(DataDir.path(file_name), contents)
    end)
  end
end
