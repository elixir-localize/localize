defmodule Localize.Inflection.Locale do
  @moduledoc false

  # Locale argument normalization. Public APIs accept locale atoms
  # (canonically BCP47, :"zh-TW") or binaries (the form carried by
  # Localize.LanguageTag.canonical_locale_id, "zh-TW"); internally
  # locales are underscore-form atoms because the upstream resource
  # names carry underscores and the data tables are keyed by atom.
  #
  # Binary input only becomes an atom after the corresponding data
  # artifact is confirmed to exist, so the atom space stays bounded
  # by the shipped data.

  alias Localize.Inflection.{DataDir, Provider}

  # The languages the Unicode inflection project supports (its
  # supported-locales groups). Inflection data is optional, so a
  # supported language whose data has not been downloaded is a
  # distinct condition from an unsupported language.
  @supported ~w(ar bg bn ca cs da de el en es fi fr gu he hi hr hu id is it
                ja kk kn ko lt ml mr ms nb nl or pa pl pt ro ru sk sr sv ta
                te th tr uk ur vi yue zh)

  @doc """
  Normalizes a locale atom, binary or `Localize.LanguageTag` to
  the internal underscore string form.

  """
  def normalize(%Localize.LanguageTag{} = language_tag) do
    normalize(Localize.LanguageTag.to_string(language_tag))
  end

  def normalize(locale) when is_atom(locale) or is_binary(locale) do
    locale |> to_string() |> String.replace("-", "_")
  end

  @doc """
  Resolves a locale to the internal locale atom whose data artifact
  is available, downloading it on demand when permitted.

  Regional locales fall back to their parent language, as in the
  upstream supported-locales groups (en_AU resolves to en, de_CH
  to de). When no artifact for the fallback chain is present locally
  and the resolved language is supported, the artifact is fetched
  from the CDN if runtime downloads are permitted (the locale
  provider's `Localize.Locale.Provider.allow_download?/0` gate,
  `false` by default).

  ### Returns

  * `{:ok, atom}` when the data is available.

  * `{:error, %Localize.InflectionDataNotAvailableError{}}` when
    the language is supported but its inflection data is not present
    and could not be downloaded (downloads disabled or fetch failed).

  * `{:error, %Localize.InflectionNotSupportedError{}}` when no
    language in the fallback chain is supported by the inflection
    data.

  """
  def resolve(locale) do
    candidates = locale |> normalize() |> chain()

    cond do
      match = Enum.find(candidates, &artifact?/1) ->
        {:ok, String.to_atom(match)}

      target = Enum.find(candidates, &(&1 in @supported)) ->
        fetch_artifact(target, locale)

      true ->
        {:error, Localize.InflectionNotSupportedError.exception(locale: locale)}
    end
  end

  # Fetches the fallback target's artifact on demand when runtime
  # downloads are permitted (reusing the locale provider's
  # `allow_download?/0` gate), writing it into the data directory so
  # the next resolve finds it locally. When downloads are disabled, or
  # the fetch fails, the data is reported not-yet-available for the
  # originally requested locale. Never raises: transport and
  # filesystem failures degrade to an error tuple.
  defp fetch_artifact(target, locale) do
    if Localize.Locale.Provider.allow_download?() do
      file_name = target <> ".etf"

      with {:ok, body} <- Provider.download_file(file_name),
           :ok <- File.mkdir_p(DataDir.dir()),
           :ok <- File.write(DataDir.path(file_name), body) do
        {:ok, String.to_atom(target)}
      else
        {:error, %{__exception__: true} = exception} ->
          {:error, exception}

        {:error, _posix} ->
          {:error, Localize.InflectionDataNotAvailableError.exception(locale: locale)}
      end
    else
      {:error, Localize.InflectionDataNotAvailableError.exception(locale: locale)}
    end
  end

  @doc """
  Returns the languages supported by the inflection data, as
  internal locale strings.

  """
  def supported, do: @supported

  @doc """
  Returns the locale fallback chain for an internal locale string,
  from most to least specific.

  """
  def chain(""), do: []
  def chain(internal), do: [internal | chain(parent(internal))]

  @doc """
  Returns the parent of an internal locale string, or "" for a
  bare language.

  """
  def parent(internal) do
    case String.split(internal, "_") do
      [_language] -> ""
      parts -> parts |> Enum.drop(-1) |> Enum.join("_")
    end
  end

  @doc """
  Returns true when a data artifact exists for the internal locale
  string.

  """
  def artifact?(internal) when is_binary(internal) do
    File.exists?(DataDir.path(internal <> ".etf"))
  end
end
