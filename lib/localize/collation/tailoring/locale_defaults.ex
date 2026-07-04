defmodule Localize.Collation.Tailoring.LocaleDefaults do
  # Preset collation option defaults for common locales.
  #
  # Maps BCP47 language tags to their standard collation option overrides
  # as defined by CLDR. These defaults are applied before any explicit
  # BCP47 `-u-` extension keys.
  #
  @moduledoc false

  @locale_defaults %{
    "cu" => [case_first: :upper],
    "da" => [case_first: :upper],
    "mt" => [case_first: :upper],
    "nb" => [case_first: :upper],
    "nn" => [case_first: :upper],
    "no" => [case_first: :upper]
  }

  @locale_type_defaults %{
    "de" => :standard,
    "es" => :standard
  }

  @doc """
  Get option overrides for a locale.

  ### Arguments

  * `locale` - a BCP47 locale string (e.g., `"da"`, `"de-AT"`, `"sv-SE"`).

  ### Returns

  A keyword list of option overrides, or an empty list if no defaults exist.

  ### Examples

      iex> Localize.Collation.Tailoring.LocaleDefaults.options_for("da")
      [case_first: :upper]

      iex> Localize.Collation.Tailoring.LocaleDefaults.options_for("en")
      []

  """
  @spec options_for(String.t()) :: keyword()
  def options_for(locale) when is_binary(locale) do
    language = extract_language(locale)

    case Map.get(@locale_defaults, language) do
      nil -> options_from_parent(language)
      defaults -> defaults
    end
  end

  defp options_from_parent(language) do
    case Localize.validate_locale(language) do
      {:ok, tag} ->
        options_from_parent_tag(tag, language)

      {:error, _} ->
        []
    end
  end

  defp options_from_parent_tag(tag, language) do
    case Localize.Locale.parent(tag) do
      {:ok, parent_tag} ->
        parent_language = parent_tag.language |> to_string()

        if parent_language != language and parent_language != "und" do
          options_for(parent_language)
        else
          []
        end

      {:error, _} ->
        []
    end
  end

  @doc """
  Get the default collation type for a locale.

  ### Arguments

  * `locale` - a BCP47 locale string.

  ### Returns

  The default collation type atom for the locale, or `:standard`.

  ### Examples

      iex> Localize.Collation.Tailoring.LocaleDefaults.default_type("de")
      :standard

      iex> Localize.Collation.Tailoring.LocaleDefaults.default_type("es")
      :standard

  """
  @spec default_type(String.t()) :: atom()
  def default_type(locale) when is_binary(locale) do
    language = extract_language(locale)
    Map.get(@locale_type_defaults, language, :standard)
  end

  @doc """
  Extract the language subtag from a BCP47 locale string.

  ### Arguments

  * `locale` - a BCP47 locale string.

  ### Returns

  The lowercase language subtag string.

  ### Examples

      iex> Localize.Collation.Tailoring.LocaleDefaults.extract_language("de-AT-u-co-phonebk")
      "de"

      iex> Localize.Collation.Tailoring.LocaleDefaults.extract_language("sv")
      "sv"

  """
  @spec extract_language(String.t()) :: String.t()
  def extract_language(locale) do
    locale
    |> String.split("-", parts: 2)
    |> hd()
    |> String.downcase()
  end
end
