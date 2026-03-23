defmodule Localize.LanguageTag.Sigil do
  @moduledoc """
  Implements a `sigil_l/2` macro for
  constructing `t:Localize.LanguageTag` structs.

  """

  @doc """
  Handles sigil `~l` for language tags.

  ## Arguments

  * `locale_id` is a [BCP 47](https://unicode-org.github.io/cldr/ldml/tr35.html#Identifiers)
    locale identifier as a string.

  ## Options

  * `u` Will parse the locale but will not add
    likely subtags or resolve the CLDR locale identifier.

  ## Returns

  * a `t:Localize.LanguageTag.t/0` struct or

  * raises an exception.

  ## Examples

      iex> import Localize.LanguageTag.Sigil
      iex> tag = ~l(en-US-u-ca-gregory)
      iex> tag.language
      :en

      iex> import Localize.LanguageTag.Sigil
      iex> tag = ~l(en)u
      iex> tag.requested_locale_id
      "en"

  """
  defmacro sigil_l(locale_id, [?u]) do
    {:<<>>, _, [locale_id]} = locale_id

    case Localize.LanguageTag.parse(locale_id) do
      {:ok, language_tag} ->
        quote do
          unquote(Macro.escape(language_tag))
        end

      {:error, exception} ->
        raise exception
    end
  end

  defmacro sigil_l(locale_id, _opts) do
    {:<<>>, _, [locale_id]} = locale_id

    case Localize.LanguageTag.new(locale_id) do
      {:ok, language_tag} ->
        quote do
          unquote(Macro.escape(language_tag))
        end

      {:error, exception} ->
        raise exception
    end
  end
end
