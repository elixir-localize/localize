defmodule Localize.Collation.Tailoring.LocaleDefaults do
  # Preset collation option defaults for common locales.
  #
  # Maps languages to their standard collation option overrides as
  # defined by CLDR. These defaults are applied before any explicit
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

  * `locale` - a `t:Localize.LanguageTag.t/0`, or a locale name as an
    atom or a binary, which is validated first.

  ### Returns

  A keyword list of option overrides, or an empty list if no defaults exist
  for the locale's language or any of its parents'.

  ### Examples

      iex> Localize.Collation.Tailoring.LocaleDefaults.options_for("da")
      [case_first: :upper]

      iex> Localize.Collation.Tailoring.LocaleDefaults.options_for("en")
      []

  """
  @spec options_for(Localize.LanguageTag.t() | atom() | String.t()) :: keyword()
  def options_for(%Localize.LanguageTag{} = language_tag) do
    case Map.get(@locale_defaults, language_of(language_tag)) do
      nil -> options_from_parent(language_tag)
      defaults -> defaults
    end
  end

  def options_for(locale) do
    case Localize.validate_locale(locale) do
      {:ok, language_tag} -> options_for(language_tag)
      {:error, _reason} -> []
    end
  end

  # A language without defaults of its own takes its parents', following
  # CLDR's inheritance through `Localize.Locale.parent/1`; the root has none.
  defp options_from_parent(language_tag) do
    case Localize.Locale.parent(language_tag) do
      {:ok, %Localize.LanguageTag{language: :und}} -> []
      {:ok, parent} -> options_for(parent)
      {:error, _no_parent} -> []
    end
  end

  @doc """
  Get the default collation type for a locale.

  ### Arguments

  * `locale` - a `t:Localize.LanguageTag.t/0`, or a locale name as an
    atom or a binary, which is validated first.

  ### Returns

  The default collation type atom for the locale, or `:standard`.

  ### Examples

      iex> Localize.Collation.Tailoring.LocaleDefaults.default_type("de")
      :standard

      iex> Localize.Collation.Tailoring.LocaleDefaults.default_type("es")
      :standard

  """
  @spec default_type(Localize.LanguageTag.t() | atom() | String.t()) :: atom()
  def default_type(%Localize.LanguageTag{} = language_tag) do
    Map.get(@locale_type_defaults, language_of(language_tag), :standard)
  end

  def default_type(locale) do
    case Localize.validate_locale(locale) do
      {:ok, language_tag} -> default_type(language_tag)
      {:error, _reason} -> :standard
    end
  end

  # The defaults are keyed by the language subtag's text, which a validated
  # tag carries as an atom.
  defp language_of(%Localize.LanguageTag{language: language}) when is_atom(language) do
    Atom.to_string(language)
  end

  defp language_of(%Localize.LanguageTag{language: language}) when is_binary(language) do
    language
  end
end
