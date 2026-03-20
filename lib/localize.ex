defmodule Localize do
  @moduledoc """
  Documentation for `Localize`.
  """

  @doc """
  Hello world.

  ## Examples

      iex> Localize.hello()
      :world

  """
  def hello do
    :world
  end

  @doc """
  Validates a locale identifier or language tag.

  Ensures that the given locale can be resolved to a known CLDR
  locale. When given a binary locale identifier, it is parsed into
  a `Localize.LanguageTag`. When given an existing language tag
  whose `:cldr_locale_id` is not yet populated, a best-match
  resolution is attempted using `Localize.LanguageTag.best_match/2`.

  ### Arguments

  * `locale` is a locale identifier binary, an atom, or a
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * `{:ok, language_tag}` where `language_tag` is a
    `t:Localize.LanguageTag.t/0` with a populated `:cldr_locale_id`.

  * `{:error, Localize.InvalidLocaleError.t()}` if the locale
    identifier cannot be parsed into a valid language tag.

  * `{:error, Localize.UnknownLocaleError.t()}` if the locale
    parses successfully but does not match any known CLDR locale.

  ### Examples

      iex> {:ok, tag} = Localize.validate_locale("en")
      iex> tag.cldr_locale_id
      :en

  """
  @spec validate_locale(Localize.LanguageTag.t() | String.t() | atom()) ::
          {:ok, Localize.LanguageTag.t()} | {:error, Exception.t()}

  def validate_locale(%Localize.LanguageTag{cldr_locale_id: cldr_locale_id} = language_tag)
      when not is_nil(cldr_locale_id) do
    {:ok, language_tag}
  end

  def validate_locale(%Localize.LanguageTag{cldr_locale_id: nil} = language_tag) do
    resolve_cldr_locale(language_tag)
  end

  def validate_locale(locale_id) when is_binary(locale_id) do
    case Localize.LanguageTag.new(locale_id) do
      {:ok, %Localize.LanguageTag{cldr_locale_id: cldr_locale_id} = language_tag}
      when not is_nil(cldr_locale_id) ->
        {:ok, language_tag}

      {:ok, %Localize.LanguageTag{cldr_locale_id: nil} = language_tag} ->
        resolve_cldr_locale(language_tag)

      {:error, _reason} ->
        {:error, Localize.InvalidLocaleError.exception(locale_id: locale_id)}
    end
  end

  def validate_locale(locale_id) when is_atom(locale_id) do
    validate_locale(Atom.to_string(locale_id))
  end

  defp resolve_cldr_locale(%Localize.LanguageTag{} = language_tag) do
    all_locale_ids = Localize.Locale.Provider.all_locale_ids()

    case Localize.LanguageTag.best_match(language_tag, all_locale_ids) do
      {:ok, cldr_locale_id, _score} ->
        {:ok, %{language_tag | cldr_locale_id: cldr_locale_id}}

      {:error, _} ->
        locale_id = Localize.LanguageTag.to_string(language_tag)
        {:error, Localize.UnknownLocaleError.exception(locale_id: locale_id)}
    end
  end
end
