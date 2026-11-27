defmodule Localize.Inflection.Locale do
  @moduledoc false

  # Locale argument normalization. Public APIs accept locale atoms
  # (canonically BCP47, :"zh-TW") or binaries (the form carried by
  # Localize.LanguageTag.canonical_locale_id, "zh-TW"); internally
  # locales are underscore-form atoms because the upstream resource
  # names carry underscores and the data tables are keyed by atom.
  #
  # A locale reads the data upstream would give it: the canonical locale,
  # then each name `upstream_fallback/1` gives, the first supported language
  # whose artifact exists. Only a supported language becomes an atom, so the
  # atom space stays bounded by the shipped data.

  alias Localize.Inflection.{DataDir, Provider}

  # The languages the Unicode inflection project supports (its
  # supported-locales groups). Inflection data is optional, so a
  # supported language whose data has not been downloaded is a
  # distinct condition from an unsupported language.
  @supported ~w(ar bg bn ca cs da de el en es fi fr gu he hi hr hu id is it
                ja kk kn ko lt ml mr ms nb nl or pa pl pt ro ru sk sr sv ta
                te th tr uk ur vi yue zh)

  # A locale is subtags of letters and digits joined by hyphens or
  # underscores. The internal form becomes a data file name, so anything
  # else names no locale: "../" in it reached files outside the data
  # directory, and each spelling of such a path minted a fresh atom.
  @locale_pattern ~r/\A[A-Za-z0-9]{1,8}(?:[-_][A-Za-z0-9]{1,8})*\z/

  @doc """
  Normalizes a locale atom, binary or `Localize.LanguageTag` to
  the internal underscore string form, without extensions:
  `"ar-SA-u-nu-arab"` is `"ar_SA"`.

  """
  def normalize(%Localize.LanguageTag{} = language_tag) do
    normalize(Localize.LanguageTag.to_string(language_tag))
  end

  # Extensions (`-u-`, `-t-`, private use `-x-`) begin at the first
  # singleton subtag. They name no inflection data, and keeping them
  # made `ar-u-nu-arab` miss every rule keyed by `ar`.
  def normalize(locale) when (is_atom(locale) and not is_nil(locale)) or is_binary(locale) do
    string = to_string(locale)

    if Regex.match?(@locale_pattern, string) do
      string
      |> String.split(["-", "_"])
      |> Enum.take_while(&(byte_size(&1) > 1))
      |> Enum.join("_")
    else
      ""
    end
  end

  # Anything else names no locale, so no data resolves for it.
  def normalize(_locale), do: ""

  @doc """
  Resolves a locale to the internal locale atom whose data artifact
  is available, downloading it on demand when permitted.

  The locale is canonicalized, so a deprecated language reads its
  replacement's data (`iw` reads `he`), then walked as upstream walks
  it, with `upstream_fallback/1`: `en-AU` reads `en`, `zh-TW` reads
  `zh` and `sr-Latn` reads `sr`. Upstream's data is found by its own
  rule, not by CLDR inheritance, whose parent for `zh-TW` (`zh-Hant`)
  is the root. When the data is not present locally, it is fetched
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
    candidates = candidates(locale)

    cond do
      match = Enum.find(candidates, &artifact?/1) ->
        {:ok, String.to_atom(match)}

      target = List.first(candidates) ->
        fetch_artifact(target, locale)

      true ->
        {:error, Localize.InflectionNotSupportedError.exception(locale: locale)}
    end
  end

  # The supported languages on the locale's walk. No supported language is
  # deprecated and every walk ends at its language, so canonicalizing can
  # change the result only where the locale as given reaches none: that
  # case alone pays for it.
  defp candidates(%Localize.LanguageTag{} = language_tag) do
    language_tag
    |> normalize()
    |> supported_on_walk()
  end

  defp candidates(locale) do
    internal = normalize(locale)

    case supported_on_walk(internal) do
      [] -> internal |> canonical() |> supported_on_walk()
      [_ | _] = candidates -> candidates
    end
  end

  defp supported_on_walk(internal) do
    internal
    |> upstream_chain()
    |> Enum.filter(&(&1 in @supported))
  end

  # The internal form of the canonical locale, so a deprecated language
  # reads its replacement (`iw` as `he`); one that does not parse stays.
  defp canonical(internal) do
    case canonical_tag(internal) do
      {:ok, language_tag} -> normalize(language_tag)
      {:error, _reason} -> internal
    end
  end

  defp canonical_tag(internal) do
    with {:ok, parsed} <- Localize.LanguageTag.parse(internal) do
      Localize.LanguageTag.canonicalize(parsed)
    end
  end

  defp upstream_chain("") do
    []
  end

  defp upstream_chain(internal) do
    [internal | upstream_chain(upstream_fallback(internal))]
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
           :ok <- written(DataDir.path(file_name), body, locale) do
        {:ok, String.to_atom(target)}
      end
    else
      unavailable(locale)
    end
  end

  # A filesystem failure is reported for the locale asked for; the posix
  # reason names a path the caller never gave.
  defp written(path, body, locale) do
    case File.mkdir_p(DataDir.dir()) do
      :ok -> written_file(path, body, locale)
      {:error, _posix} -> unavailable(locale)
    end
  end

  defp written_file(path, body, locale) do
    case File.write(path, body) do
      :ok -> :ok
      {:error, _posix} -> unavailable(locale)
    end
  end

  defp unavailable(locale) do
    {:error, Localize.InflectionDataNotAvailableError.exception(locale: locale)}
  end

  @doc """
  Returns the languages supported by the inflection data, as
  internal locale strings.

  """
  def supported, do: @supported

  @doc """
  Returns the name upstream falls back to from an internal locale
  string: the name with its last subtag dropped, ICU's
  `ULocale::getFallback`, which upstream's `LocaleUtils::getFallbackPair`
  applies where its own fallbacks name nothing; `""` for a bare
  language. This names upstream's resources the way upstream does; it is
  not locale inheritance, which `Localize.Locale.parent/2` gives.

  """
  def upstream_fallback(internal) when is_binary(internal) do
    case String.split(internal, "_") do
      [_language] -> ""
      subtags -> subtags |> Enum.drop(-1) |> Enum.join("_")
    end
  end

  @doc """
  Returns the language subtag of an internal locale string: `"tr"` for
  `"tr_Latn_TR"`, and `""` for `""`.

  """
  def language(internal) when is_binary(internal) do
    internal
    |> String.split("_")
    |> hd()
  end

  @doc """
  Returns true when a data artifact exists for the internal locale
  string.

  """
  def artifact?(internal) when is_binary(internal) do
    File.exists?(DataDir.path(internal <> ".etf"))
  end
end
