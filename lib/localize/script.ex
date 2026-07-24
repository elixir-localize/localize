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
    locale = Keyword.get(options, :locale, Localize.get_locale())

    with {:ok, style} <- validate_style(Keyword.get(options, :style, :standard)),
         {:ok, fallback} <- validate_fallback(Keyword.get(options, :fallback, false)),
         {:ok, script_atom} <- normalize_script_code(script),
         {:ok, locale_id} <- Localize.Locale.cldr_locale_id_from(locale) do
      case lookup_script(script_atom, locale_id, style) do
        {:ok, _} = result ->
          result

        {:error, _} = error ->
          display_name_fallback(fallback, script_atom, style, error)
      end
    end
  end

  defp display_name_fallback(true, script_atom, style, _error) do
    with {:ok, default_locale_id} <-
           Localize.Locale.cldr_locale_id_from(Localize.default_locale()) do
      lookup_script(script_atom, default_locale_id, style)
    end
  end

  defp display_name_fallback(false, _script_atom, _style, error) do
    error
  end

  @doc """
  Same as `display_name/2` but raises on error.

  ### Arguments

  * `script` is a script code atom or string (e.g., `:Latn`,
    `"Cyrl"`).

  * `options` is a keyword list of options.

  ### Options

  * See `display_name/2` for the supported options.

  ### Returns

  * The localized script name as a string.

  * Raises an exception if the script code is not found
    in the locale.

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

  # ── Per-locale script data ──────────────────────────────────

  @doc """
  Returns a sorted list of script codes that have localized names
  in a locale.

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

      iex> {:ok, codes} = Localize.Script.scripts_for()
      iex> :Latn in codes
      true

  """
  @spec scripts_for(Keyword.t()) ::
          {:ok, [atom()]} | {:error, Exception.t()}
  def scripts_for(options \\ []) do
    locale = Keyword.get(options, :locale, Localize.get_locale())

    with {:ok, locale_id} <- Localize.Locale.cldr_locale_id_from(locale),
         {:ok, scripts} <- load_scripts(locale_id) do
      {:ok, scripts |> Map.keys() |> Enum.sort()}
    end
  end

  @doc """
  Returns a map of script codes to their localized names in a
  locale.

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

      iex> {:ok, scripts} = Localize.Script.script_names_for()
      iex> scripts[:Latn]
      %{standard: "Latin"}

  """
  @spec script_names_for(Keyword.t()) ::
          {:ok, %{atom() => map()}} | {:error, Exception.t()}
  def script_names_for(options \\ []) do
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
          resolve_script_name(names, style, script_atom)

        :error ->
          {:error, Localize.UnknownScriptError.exception(script: script_atom)}
      end
    end
  end

  defp resolve_script_name(names, style, script_atom) do
    case resolve_style(names, style) do
      {:ok, _} = result ->
        result

      :error ->
        case Map.fetch(names, :standard) do
          {:ok, _} = result -> result
          :error -> {:error, Localize.UnknownScriptError.exception(script: script_atom)}
        end
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
