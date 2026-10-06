defmodule Localize.Inflection.NumberConcept do
  @moduledoc false

  # A number as the inflection functions write it, ported from the
  # upstream `NumberConcept`: digits in the locale's decimal format,
  # words from one of its RBNF rule sets, or digits spoken as words.
  # A rule set the locale lacks falls back to its default,
  # `spellout-numbering` (TR35's "default used when there is no context
  # for the number") or `digits-ordinal`, and that to the
  # best rules the locale has. Results are speakable strings.

  alias Localize.Inflection.SpeakableString

  # The locale's digits, spoken as written except where upstream speaks
  # a regional format as the language's own (`getAsDigits`).
  def digits(number, locale) do
    with {:ok, print} <- Localize.Number.to_string(number, locale: locale),
         {:ok, speak} <- spoken_digits(number, locale, print) do
      {:ok, SpeakableString.new(print, speak)}
    end
  end

  # Words from `spellout-<variant>`, by default `spellout-numbering`.
  def words(number, locale, variant \\ nil) do
    format_with_rule_sets(number, rule_sets("spellout-", variant, "numbering", :spellout), locale)
  end

  # Digits whose spoken form is the words (`asSpokenWords`). Where the
  # locale has no words for the number the digits are spoken, as CLDR's
  # root rules speak them.
  def spoken_words(number, locale, variant \\ nil) do
    with {:ok, print} <- Localize.Number.to_string(number, locale: locale) do
      case words(number, locale, variant) do
        {:ok, speak} -> {:ok, SpeakableString.new(print, speak)}
        {:error, _reason} -> {:ok, print}
      end
    end
  end

  # Ordinal digits from `digits-<variant>`, by default `digits-ordinal`.
  def ordinal_digits(number, locale, variant \\ nil) do
    format_with_rule_sets(number, rule_sets("digits-", variant, "ordinal", :ordinal), locale)
  end

  # The whole part of the number, truncated as upstream's `longValue`
  # truncates it.
  def whole(number) when is_integer(number), do: number
  def whole(number) when is_float(number), do: trunc(number)
  def whole(%Decimal{} = number), do: number |> Decimal.round(0, :down) |> Decimal.to_integer()

  defp rule_sets(prefix, nil, default, best), do: [prefix <> default, best]
  defp rule_sets(prefix, variant, default, best), do: [prefix <> variant, prefix <> default, best]

  defp format_with_rule_sets(number, [rule_set | fallbacks], locale) do
    case Localize.Number.Rbnf.to_string(number, rule_set, locale: locale) do
      {:error, _reason} when fallbacks != [] -> format_with_rule_sets(number, fallbacks, locale)
      result -> result
    end
  end

  # Austrian and Swiss German speak Germany's digits and Swiss Italian
  # Italy's; Swiss French speaks France's below sixty and Belgian
  # French its own, and both speak words above.
  defp spoken_digits(number, locale, print) do
    case Localize.validate_locale(locale) do
      {:ok, %{language: language, territory: territory}} ->
        regional_digits(language, territory, number, locale, print)

      {:error, _reason} ->
        {:ok, print}
    end
  end

  defp regional_digits(:de, territory, number, _locale, _print) when territory in [:AT, :CH],
    do: Localize.Number.to_string(number, locale: "de-DE")

  defp regional_digits(:it, :CH, number, _locale, _print),
    do: Localize.Number.to_string(number, locale: "it-IT")

  defp regional_digits(:fr, :CH, number, locale, _print) do
    if abs(whole(number)) < 60,
      do: Localize.Number.to_string(number, locale: "fr-FR"),
      else: words(number, locale)
  end

  defp regional_digits(:fr, :BE, number, locale, print) do
    if abs(whole(number)) < 60, do: {:ok, print}, else: words(number, locale)
  end

  defp regional_digits(_language, _territory, _number, _locale, print), do: {:ok, print}
end
