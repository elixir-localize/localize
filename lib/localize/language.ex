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

      iex> Localize.Language.display_name("ja")
      {:ok, "Japanese"}

  """
  @spec display_name(String.t() | LanguageTag.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def display_name(language, options \\ []) do
    style = validate_style!(Keyword.get(options, :style, :standard))
    locale = Keyword.get(options, :locale, Localize.get_locale())
    fallback = validate_fallback!(Keyword.get(options, :fallback, false))

    language_code = extract_language_code(language)
    locale_id = Localize.Locale.to_locale_id(locale)

    case lookup_language(language_code, locale_id, style) do
      {:ok, _} = result ->
        result

      {:error, _} = error ->
        if fallback do
          default_locale_id = Localize.Locale.to_locale_id(Localize.default_locale())
          lookup_language(language_code, default_locale_id, style)
        else
          error
        end
    end
  end

  @doc """
  Same as `display_name/2` but raises on error.

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

  # ── Available and known languages ───────────────────────────

  @doc """
  Returns a sorted list of language codes available in a locale.

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

      iex> {:ok, codes} = Localize.Language.available_languages()
      iex> "en" in codes
      true

      iex> {:ok, codes} = Localize.Language.available_languages(locale: :de)
      iex> "en" in codes
      true

  """
  @spec available_languages(Keyword.t()) ::
          {:ok, [String.t()]} | {:error, Exception.t()}
  def available_languages(options \\ []) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    locale_id = Localize.Locale.to_locale_id(locale)

    with {:ok, languages} <- Localize.Locale.get(locale_id, [:languages]) do
      {:ok, languages |> Map.keys() |> Enum.sort()}
    end
  end

  @doc """
  Returns a map of all language codes to their localized names
  in a locale.

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

      iex> {:ok, languages} = Localize.Language.known_languages()
      iex> languages["de"]
      %{standard: "German"}

      iex> {:ok, languages} = Localize.Language.known_languages(locale: :de)
      iex> languages["en"]
      %{standard: "Englisch"}

  """
  @spec known_languages(Keyword.t()) ::
          {:ok, %{String.t() => map()}} | {:error, Exception.t()}
  def known_languages(options \\ []) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    locale_id = Localize.Locale.to_locale_id(locale)
    Localize.Locale.get(locale_id, [:languages])
  end

  # ── Private helpers ─────────────────────────────────────────

  defp extract_language_code(%LanguageTag{language: language}), do: Atom.to_string(language)
  defp extract_language_code(code) when is_binary(code), do: code
  defp extract_language_code(code) when is_atom(code), do: Atom.to_string(code)

  defp lookup_language(language_code, locale_id, style) do
    with {:ok, languages} <- Localize.Locale.get(locale_id, [:languages]) do
      case Map.fetch(languages, language_code) do
        {:ok, names} ->
          case resolve_style(names, style) do
            {:ok, _} = result ->
              result

            :error ->
              case Map.fetch(names, :standard) do
                {:ok, _} = result -> result
                :error -> {:error, Localize.UnknownLanguageError.exception(language: language_code)}
              end
          end

        :error ->
          {:error, Localize.UnknownLanguageError.exception(language: language_code)}
      end
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

  defp validate_style!(style) when style in @styles, do: style

  defp validate_style!(style) do
    raise ArgumentError,
          "Invalid :style option #{inspect(style)} supplied. " <>
            "Valid styles are #{inspect(@styles)}."
  end

  defp validate_fallback!(fallback) when is_boolean(fallback), do: fallback

  defp validate_fallback!(fallback) do
    raise ArgumentError,
          "Invalid :fallback option #{inspect(fallback)} supplied. " <>
            "Valid fallbacks are #{inspect([true, false])}."
  end
end
