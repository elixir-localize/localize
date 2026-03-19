defmodule Localize.LanguageTag.Sigil do
  @moduledoc """
  Implements a `sigil_l/2` macro for
  constructing `t:Localize.LanguageTag` structs.

  """

  @doc """
  Handles sigil `~l` for language tags.

  ## Arguments

  * `locale_name` is a [BCP 47](https://unicode-org.github.io/cldr/ldml/tr35.html#Identifiers)
    locale name as a string.

  ## Options

  * `u` Will parse the locale but will not add
    likely subtags or resolve the CLDR locale name.

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
      iex> tag.requested_locale_name
      "en"

  """
  defmacro sigil_l(locale_name, [?u]) do
    {:<<>>, _, [locale_name]} = locale_name

    case Localize.LanguageTag.parse(locale_name) do
      {:ok, language_tag} ->
        quote do
          unquote(Macro.escape(language_tag))
        end

      {:error, {exception, reason}} ->
        raise exception, reason
    end
  end

  defmacro sigil_l(locale_name, _opts) do
    {:<<>>, _, [locale_name]} = locale_name

    case Localize.LanguageTag.new(locale_name) do
      {:ok, language_tag} ->
        quote do
          unquote(Macro.escape(language_tag))
        end

      {:error, {exception, reason}} ->
        raise exception, reason
    end
  end
end
