defmodule Localize.Script do
  @moduledoc """
  Provides script name localization functions built on the
  Unicode CLDR repository.

  Script display names are loaded on demand from the locale
  data provider. Each locale provides localized names for
  script codes in one or more styles.

  ## Styles

  Script display names come in several styles:

  * `:standard` — the default form, suitable for combining with
    a language name in a locale pattern (e.g., "Simplified").

  * `:short` — a shorter form when available (e.g., "UCAS"
    instead of "Unified Canadian Aboriginal Syllabics"). Falls
    back to `:standard` when unavailable.

  * `:stand_alone` — a stand-alone form when the script name
    differs from its combined form (e.g., "Simplified Han"
    instead of "Simplified"). Falls back to `:standard` when
    unavailable.

  * `:variant` — an alternative variant name (e.g.,
    "Perso-Arabic" instead of "Arabic"). Falls back to
    `:standard` when unavailable.

  """

  alias Localize.Utils.Helpers

  @styles [:standard, :short, :stand_alone, :variant]

  # ── Display names ───────────────────────────────────────────

  @doc """
  Returns the localized display name for a script code.

  ### Arguments

  * `script` is a script code atom or string (e.g., `:Latn`,
    `"Cyrl"`).

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is
    `Localize.get_locale()`.

  * `:style` is one of `:standard`, `:short`, `:stand_alone`,
    or `:variant`. The default is `:standard`. If the requested
    style is not available for a script, falls back to
    `:standard`.

  * `:fallback` is a boolean. When `true` and the script
    is not found in the specified locale, falls back to the
    default locale. The default is `false`.

  ### Returns

  * `{:ok, name}` where `name` is the localized script name.

  * `{:error, exception}` if the script code is not found
    in the locale.

  ### Examples

      iex> Localize.Script.display_name(:Latn)
      {:ok, "Latin"}

      iex> Localize.Script.display_name("Cyrl")
      {:ok, "Cyrillic"}

      iex> Localize.Script.display_name(:Hans, style: :stand_alone)
      {:ok, "Simplified Han"}

      iex> Localize.Script.display_name(:Arab, style: :variant)
      {:ok, "Perso-Arabic"}

  """
  @spec display_name(atom() | String.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def display_name(script, options \\ []) do
    style = validate_style!(Keyword.get(options, :style, :standard))
    locale = Keyword.get(options, :locale, Localize.get_locale())
    fallback = validate_fallback!(Keyword.get(options, :fallback, false))

    with {:ok, script_atom} <- normalize_script_code(script),
         {:ok, locale_id} <- Localize.Locale.cldr_locale_id_from(locale) do
      case lookup_script(script_atom, locale_id, style) do
        {:ok, _} = result ->
          result

        {:error, _} = error ->
          if fallback do
            with {:ok, default_locale_id} <-
                   Localize.Locale.cldr_locale_id_from(Localize.default_locale()) do
              lookup_script(script_atom, default_locale_id, style)
            end
          else
            error
          end
      end
    end
  end

  @doc """
  Same as `display_name/2` but raises on error.

  ### Examples

      iex> Localize.Script.display_name!(:Latn)
      "Latin"

      iex> Localize.Script.display_name!(:Hans, style: :stand_alone)
      "Simplified Han"

  """
  @spec display_name!(atom() | String.t(), Keyword.t()) :: String.t()
  def display_name!(script, options \\ []) do
    case display_name(script, options) do
      {:ok, name} -> name
      {:error, exception} -> raise exception
    end
  end

  # ── Available and known scripts ─────────────────────────────

  @doc """
  Returns a sorted list of script codes available in a locale.

  ### Arguments

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is
    `Localize.get_locale()`.

  ### Returns

  * `{:ok, codes}` where `codes` is a sorted list of script
    code atoms.

  * `{:error, exception}` if the locale data cannot be loaded.

  ### Examples

      iex> {:ok, codes} = Localize.Script.available_scripts()
      iex> :Latn in codes
      true

  """
  @spec available_scripts(Keyword.t()) ::
          {:ok, [atom()]} | {:error, Exception.t()}
  def available_scripts(options \\ []) do
    locale = Keyword.get(options, :locale, Localize.get_locale())

    with {:ok, locale_id} <- Localize.Locale.cldr_locale_id_from(locale),
         {:ok, scripts} <- load_scripts(locale_id) do
      {:ok, scripts |> Map.keys() |> Enum.sort()}
    end
  end

  @doc """
  Returns a map of all script codes to their localized names
  in a locale.

  ### Arguments

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is
    `Localize.get_locale()`.

  ### Returns

  * `{:ok, scripts_map}` where `scripts_map` is a map of
    `%{script_atom => %{standard: name, ...}}`.

  * `{:error, exception}` if the locale data cannot be loaded.

  ### Examples

      iex> {:ok, scripts} = Localize.Script.known_scripts()
      iex> scripts[:Latn]
      %{standard: "Latin"}

  """
  @spec known_scripts(Keyword.t()) ::
          {:ok, %{atom() => map()}} | {:error, Exception.t()}
  def known_scripts(options \\ []) do
    locale = Keyword.get(options, :locale, Localize.get_locale())

    with {:ok, locale_id} <- Localize.Locale.cldr_locale_id_from(locale) do
      load_scripts(locale_id)
    end
  end

  # ── Private helpers ─────────────────────────────────────────

  defp normalize_script_code(code) when is_atom(code), do: {:ok, code}

  defp normalize_script_code(code) when is_binary(code) do
    # Gate atomisation on membership in the validity set so an unknown
    # binary script code can't grow the atom table. Script atoms for
    # known CLDR scripts are populated by SupplementalData at startup.
    case Helpers.existing_atom(code) do
      nil -> {:error, Localize.UnknownScriptError.exception(script: code)}
      atom -> {:ok, atom}
    end
  end

  defp load_scripts(locale_id) do
    with {:ok, locale_display_names} <- Localize.Locale.get(locale_id, [:locale_display_names]) do
      {:ok, Map.get(locale_display_names, :script, %{})}
    end
  end

  defp lookup_script(script_atom, locale_id, style) do
    with {:ok, scripts} <- load_scripts(locale_id) do
      case Map.fetch(scripts, script_atom) do
        {:ok, names} ->
          case resolve_style(names, style) do
            {:ok, _} = result ->
              result

            :error ->
              case Map.fetch(names, :standard) do
                {:ok, _} = result -> result
                :error -> {:error, Localize.UnknownScriptError.exception(script: script_atom)}
              end
          end

        :error ->
          {:error, Localize.UnknownScriptError.exception(script: script_atom)}
      end
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
    raise Localize.InvalidValueError.exception(
            value: style,
            expected: :style,
            allowed_values: @styles
          )
  end

  defp validate_fallback!(fallback) when is_boolean(fallback), do: fallback

  defp validate_fallback!(fallback) do
    raise Localize.InvalidValueError.exception(
            value: fallback,
            expected: :fallback,
            allowed_values: [true, false]
          )
  end
end
