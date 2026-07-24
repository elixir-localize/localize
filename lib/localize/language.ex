defmodule Localize.Language do
  @moduledoc """
  Provides language name localization functions built on the
  Unicode CLDR repository.

  Language display names are loaded on demand from the locale
  data provider. Each locale provides localized names for
  hundreds of language codes in one or more styles.

  ## Styles

  Language display names come in several styles:

  * `:standard` — the full display name (default).

  * `:short` — a shorter form when available (e.g., "Azeri"
    instead of "Azerbaijani"). Falls back to `:standard`
    when unavailable.

  * `:long` — a longer form when available (e.g., "Mandarin
    Chinese" instead of "Chinese"). Falls back to `:standard`
    when unavailable.

  * `:menu` — a menu-friendly form with the language family
    first (e.g., "Chinese, Mandarin" instead of "Mandarin
    Chinese"). Falls back to `:standard` when unavailable.

  * `:variant` — an alternative variant name (e.g., "Pushto"
    instead of "Pashto"). Falls back to `:standard` when
    unavailable.

  """

  alias Localize.LanguageTag

  @styles [:standard, :short, :long, :menu, :variant]

  # ── Display names ───────────────────────────────────────────

  @doc """
  Returns the localized display name for a language code.

  ### Arguments

  * `language` is a language code string (e.g., `"de"`,
    `"en-GB"`) or a `t:Localize.LanguageTag.t/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is
    `Localize.get_locale()`.

  * `:style` is one of `:standard`, `:short`, `:long`, `:menu`,
    or `:variant`. The default is `:standard`. If the requested
    style is not available for a language, falls back to
    `:standard`.

  * `:fallback` is a boolean. When `true` and the language
    is not found in the specified locale, falls back to the
    default locale. The default is `false`.

  ### Returns

  * `{:ok, name}` where `name` is the localized language name.

  * `{:error, exception}` if the language code is not found
    in the locale.

  ### Examples

      iex> Localize.Language.display_name("de")
      {:ok, "German"}

      iex> Localize.Language.display_name("en-GB", style: :short)
      {:ok, "UK English"}

      iex> Localize.Language.display_name("en", locale: :de)
      {:ok, "Englisch"}

      iex> Localize.Language.display_name("pt-BR")
      {:ok, "Brazilian Portuguese"}

      iex> Localize.Language.display_name("ar-SA")
      {:ok, "Arabic"}

      iex> Localize.Language.display_name("ja")
      {:ok, "Japanese"}

  A bare language keeps its own name; an explicit region resolves to
  the region-specific name where CLDR defines one (per TR35 the display
  lookup canonicalizes but does not add likely subtags):

      iex> Localize.Language.display_name("en")
      {:ok, "English"}

      iex> Localize.Language.display_name("en-US")
      {:ok, "American English"}

  """
  @spec display_name(String.t() | LanguageTag.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def display_name(language, options \\ []) do
    locale = Keyword.get(options, :locale, Localize.get_locale())

    with {:ok, style} <- validate_style(Keyword.get(options, :style, :standard)),
         {:ok, fallback} <- validate_fallback(Keyword.get(options, :fallback, false)),
         {:ok, language_tag} <- Localize.validate_locale(language),
         {:ok, locale_id} <- Localize.Locale.cldr_locale_id_from(locale) do
      case lookup_language(language_tag, locale_id, style) do
        {:ok, _} = result -> result
        {:error, _} = error -> maybe_fallback_lookup(error, fallback, language_tag, style)
      end
    end
  end

  # When `:fallback` is enabled, retry the lookup against the default
  # locale; otherwise propagate the original error unchanged.
  defp maybe_fallback_lookup(_error, true, language_tag, style) do
    with {:ok, default_locale_id} <-
           Localize.Locale.cldr_locale_id_from(Localize.default_locale()) do
      lookup_language(language_tag, default_locale_id, style)
    end
  end

  defp maybe_fallback_lookup(error, false, _language_tag, _style), do: error

  @doc """
  Same as `display_name/2` but raises on error.

  ### Arguments

  * `language` is a language code string (e.g., `"de"`,
    `"en-GB"`) or a `t:Localize.LanguageTag.t/0`.

  * `options` is a keyword list of options.

  ### Options

  * See `display_name/2` for the supported options.

  ### Returns

  * The localized language name as a string.

  * Raises an exception if the language code is not found
    in the locale.

  ### Examples

      iex> Localize.Language.display_name!("de")
      "German"

      iex> Localize.Language.display_name!("en-GB", style: :short)
      "UK English"

  """
  @spec display_name!(String.t() | LanguageTag.t(), Keyword.t()) :: String.t()
  def display_name!(language, options \\ []) do
    case display_name(language, options) do
      {:ok, name} -> name
      {:error, exception} -> raise exception
    end
  end

  # ── Per-locale language data ─────────────────────────────────

  @doc """
  Returns a sorted list of language codes that have localized
  names in a locale.

  ### Arguments

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is
    `Localize.get_locale()`.

  ### Returns

  * `{:ok, codes}` where `codes` is a sorted list of language
    code strings.

  * `{:error, exception}` if the locale data cannot be loaded.

  ### Examples

      iex> {:ok, codes} = Localize.Language.languages_for()
      iex> "en" in codes
      true

      iex> {:ok, codes} = Localize.Language.languages_for(locale: :de)
      iex> "en" in codes
      true

  """
  @spec languages_for(Keyword.t()) ::
          {:ok, [String.t()]} | {:error, Exception.t()}
  def languages_for(options \\ []) do
    locale = Keyword.get(options, :locale, Localize.get_locale())

    with {:ok, locale_id} <- Localize.Locale.cldr_locale_id_from(locale),
         {:ok, languages} <- Localize.Locale.get(locale_id, [:languages]) do
      {:ok, languages |> Map.keys() |> Enum.sort()}
    end
  end

  @doc """
  Returns a map of language codes to their localized names in a
  locale.

  ### Arguments

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is
    `Localize.get_locale()`.

  ### Returns

  * `{:ok, languages_map}` where `languages_map` is a map of
    `%{language_code => %{standard: name, ...}}`.

  * `{:error, exception}` if the locale data cannot be loaded.

  ### Examples

      iex> {:ok, languages} = Localize.Language.language_names_for()
      iex> languages["de"]
      %{standard: "German"}

      iex> {:ok, languages} = Localize.Language.language_names_for(locale: :de)
      iex> languages["en"]
      %{standard: "Englisch"}

  """
  @spec language_names_for(Keyword.t()) ::
          {:ok, %{String.t() => map()}} | {:error, Exception.t()}
  def language_names_for(options \\ []) do
    locale = Keyword.get(options, :locale, Localize.get_locale())

    with {:ok, locale_id} <- Localize.Locale.cldr_locale_id_from(locale) do
      Localize.Locale.get(locale_id, [:languages])
    end
  end

  # ── Private helpers ─────────────────────────────────────────

  defp lookup_language(language_tag, locale_id, style) do
    with {:ok, languages} <- Localize.Locale.get(locale_id, [:languages]) do
      language_tag
      |> candidate_codes()
      |> first_matching_name(languages, style)
      |> case do
        {:ok, _} = result ->
          result

        :error ->
          {:error,
           Localize.UnknownLanguageError.exception(language: language_tag.canonical_locale_id)}
      end
    end
  end

  # Builds candidate CLDR language keys from the most specific subtag
  # combination to the least, mirroring the CLDR locale display name
  # fallback order used by `Localize.Locale.LocaleDisplay`:
  # lang-script-territory → lang-script → lang-territory → lang. Per
  # TR35 the tie between the two-subtag forms is broken in favour of the
  # subtag matching earlier in the identifier, so `lang-script` is tried
  # before `lang-territory`.
  #
  # The subtags are taken from the canonical-syntax form carried in
  # `canonical_locale_id` — the caller's request with aliases resolved
  # but no likely-subtags added — rather than the maximized struct
  # fields. Per TR35 the display algorithm canonicalizes but does not
  # maximize, so bare `"en"` resolves to "English" (not "American
  # English") while an explicit `"en-GB"` still resolves to "British
  # English". Falls back to the maximized fields when no canonical id is
  # present (e.g. a hand-built tag).
  defp candidate_codes(%LanguageTag{} = tag) do
    {language, script, territory} = display_subtags(tag)

    [
      code_from(language, script, territory),
      code_from(language, script, nil),
      code_from(language, nil, territory),
      code_from(language, nil, nil)
    ]
    |> Enum.uniq()
  end

  defp display_subtags(%LanguageTag{canonical_locale_id: id} = tag) when is_binary(id) do
    case LanguageTag.parse(id) do
      {:ok, %LanguageTag{language: language, script: script, territory: territory}} ->
        {language, script, territory}

      _ ->
        {tag.language, tag.script, tag.territory}
    end
  end

  defp display_subtags(%LanguageTag{} = tag), do: {tag.language, tag.script, tag.territory}

  defp code_from(language, script, territory) do
    [language, script, territory]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join("-", &to_string/1)
  end

  # Returns the localized name for the first candidate code present in
  # the locale data, honoring the requested style and falling back to
  # the standard style for that same code before moving to the next,
  # less specific, candidate.
  defp first_matching_name([], _languages, _style), do: :error

  defp first_matching_name([code | rest], languages, style) do
    with {:ok, names} <- Map.fetch(languages, code),
         {:ok, _} = result <- resolve_style_with_standard(names, style) do
      result
    else
      _ -> first_matching_name(rest, languages, style)
    end
  end

  defp resolve_style_with_standard(names, style) do
    case resolve_style(names, style) do
      {:ok, _} = result -> result
      :error -> resolve_style(names, :standard)
    end
  end

  # The :menu style stores a nested map with :alt (the composed
  # display string), :core, and :extension keys. Return the :alt
  # value as the display name.
  defp resolve_style(names, :menu) do
    case Map.fetch(names, :menu) do
      {:ok, %{alt: alt}} when is_binary(alt) -> {:ok, alt}
      _ -> :error
    end
  end

  defp resolve_style(names, style) do
    case Map.fetch(names, style) do
      {:ok, value} when is_binary(value) -> {:ok, value}
      _ -> :error
    end
  end

  # Invalid option values return error tuples like every other input
  # error, so the same failure class always exits through the same
  # channel; the `!` variants raise for all of them uniformly.
  defp validate_style(style) when style in @styles, do: {:ok, style}

  defp validate_style(style) do
    {:error,
     Localize.InvalidValueError.exception(
       value: style,
       expected: :style,
       allowed_values: @styles
     )}
  end

  defp validate_fallback(fallback) when is_boolean(fallback), do: {:ok, fallback}

  defp validate_fallback(fallback) do
    {:error,
     Localize.InvalidValueError.exception(
       value: fallback,
       expected: :fallback,
       allowed_values: [true, false]
     )}
  end
end
