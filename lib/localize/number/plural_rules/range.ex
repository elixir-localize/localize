defmodule Localize.Number.PluralRule.Range do
  @moduledoc """
  Plural category selection for numeric ranges.

  Implements the [TR35 plural ranges](https://unicode.org/reports/tr35/tr35-numbers.html#Plural_Ranges) rules: the plural category of a range like "1–2 days" is derived from the categories of its endpoints using per-language range rules from the CLDR supplemental data. The primary functions are `plural_rule/3` for endpoint categories and `plural_rule_for/3` for endpoint numbers.

  """

  @plural_categories [:zero, :one, :two, :few, :many, :other]

  @doc """
  Returns the plural category for a range given the categories of its endpoints.

  ### Arguments

  * `start_category` is the plural category of the range start.

  * `end_category` is the plural category of the range end.

  * `locale` is a locale identifier atom, string, or a `t:Localize.LanguageTag.t/0` struct.

  ### Returns

  * `{:ok, category}` where `category` is one of `:zero`, `:one`, `:two`, `:few`, `:many`, or `:other`.

  * `{:error, exception}` if the locale is invalid.

  ### Examples

      iex> Localize.Number.PluralRule.Range.plural_rule(:one, :other, "fr")
      {:ok, :other}

      iex> Localize.Number.PluralRule.Range.plural_rule(:one, :one, "fr")
      {:ok, :one}

  """
  @spec plural_rule(atom(), atom(), atom() | String.t() | Localize.LanguageTag.t()) ::
          {:ok, atom()} | {:error, Exception.t()}
  def plural_rule(start_category, end_category, locale)
      when start_category in @plural_categories and end_category in @plural_categories do
    with {:ok, language_tag} <- Localize.validate_locale(locale) do
      language = Kernel.to_string(language_tag.language)
      {:ok, resolve_range(language, start_category, end_category)}
    end
  end

  @doc """
  Returns the plural category for a range given the numbers of its endpoints.

  The endpoint categories are selected with the locale's cardinal plural rules, then combined with `plural_rule/3`.

  ### Arguments

  * `start_number` is the start of the range (integer, float, or Decimal).

  * `end_number` is the end of the range.

  * `locale` is a locale identifier atom, string, or a `t:Localize.LanguageTag.t/0` struct.

  ### Returns

  * `{:ok, category}` where `category` is one of `:zero`, `:one`, `:two`, `:few`, `:many`, or `:other`.

  * `{:error, exception}` if the locale is invalid.

  ### Examples

      iex> Localize.Number.PluralRule.Range.plural_rule_for(0, 1, "fr")
      {:ok, :one}

      iex> Localize.Number.PluralRule.Range.plural_rule_for(1, 2, "fr")
      {:ok, :other}

  """
  @spec plural_rule_for(
          number() | Decimal.t(),
          number() | Decimal.t(),
          atom() | String.t() | Localize.LanguageTag.t()
        ) :: {:ok, atom()} | {:error, Exception.t()}
  def plural_rule_for(start_number, end_number, locale) do
    with {:ok, language_tag} <- Localize.validate_locale(locale) do
      start_category = Localize.Number.PluralRule.Cardinal.plural_rule(start_number, language_tag)
      end_category = Localize.Number.PluralRule.Cardinal.plural_rule(end_number, language_tag)
      plural_rule(start_category, end_category, language_tag)
    end
  end

  # TR35 plural ranges: a <start, end> pair without an explicit rule —
  # including languages with no plural-ranges data — resolves to the
  # end category.
  defp resolve_range(language, start_category, end_category) do
    ranges =
      Enum.find_value(Localize.SupplementalData.plural_ranges(), [], fn entry ->
        if language in entry.locales, do: entry.ranges
      end)

    Enum.find_value(ranges, end_category, fn
      %{start: ^start_category, end: ^end_category, result: result} -> result
      _range -> nil
    end)
  end
end
