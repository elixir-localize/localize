defmodule Localize.Number.PluralRule.Ordinal do
  @moduledoc """
  Implements ordinal plural rules for numbers.

  Ordinal plural rules are used for ordering sequences
  (e.g., "1st", "2nd", "3rd", "4th"). Each locale has its
  own set of rules that classify a number into one of the
  plural categories: `:zero`, `:one`, `:two`, `:few`,
  `:many`, or `:other`.

  All plural rule functions are generated at compile time
  from the CLDR plural rules data.

  """

  alias Localize.Utils.Digits
  alias Localize.Utils.Math

  import Digits,
    only: [number_of_integer_digits: 1, remove_trailing_zeros: 1, fraction_as_integer: 2]

  import Math, only: [mod: 2, within: 2]
  import Localize.Number.PluralRule.Transformer

  alias Localize.LanguageTag

  @rules Localize.Number.PluralRule.load_plural_rules(:ordinal)

  @rules_locales Localize.SupplementalData.plural_rules_locales(:ordinal)

  @doc """
  Returns the locale names for which ordinal plural rules
  are defined.

  ### Returns

  * A sorted list of locale name atoms.

  """
  @spec available_locale_names :: [atom(), ...]
  def available_locale_names do
    @rules_locales
  end

  @doc """
  Returns all the ordinal plural rules defined in CLDR.

  ### Returns

  * A map of locale names to their parsed plural rule definitions.

  """
  def plural_rules do
    @rules
  end

  @doc """
  Pluralize a number using ordinal plural rules and a
  substitution map.

  ### Arguments

  * `number` is an integer, float, or Decimal.

  * `locale` is a locale name string or atom, or a
    `t:Localize.LanguageTag.t/0`.

  * `substitutions` is a map that maps plural categories to
    substitution values. The valid keys are `:zero`, `:one`,
    `:two`, `:few`, `:many`, and `:other`.

  ### Returns

  * The substitution value for the plural category of the
    given number, or `nil` if no matching substitution is found.

  ### Examples

      iex> Localize.Number.PluralRule.Ordinal.pluralize(1, "en", %{one: "st", two: "nd", few: "rd", other: "th"})
      "st"

      iex> Localize.Number.PluralRule.Ordinal.pluralize(2, "en", %{one: "st", two: "nd", few: "rd", other: "th"})
      "nd"

  """
  @default_substitution :other

  def pluralize(number, locale_name, substitutions)
      when is_atom(locale_name) or is_binary(locale_name) do
    with {:ok, parsed} <- LanguageTag.parse(to_string(locale_name)),
         {:ok, language_tag} <- LanguageTag.canonicalize(parsed) do
      pluralize(number, language_tag, substitutions)
    end
  end

  def pluralize(number, %LanguageTag{} = locale, %{} = substitutions)
      when is_number(number) do
    do_pluralize(number, locale, substitutions)
  end

  def pluralize(%Decimal{sign: _sign, coef: coef, exp: 0} = number, locale, substitutions)
      when is_integer(coef) do
    number
    |> Decimal.to_integer()
    |> do_pluralize(locale, substitutions)
  end

  def pluralize(%Decimal{sign: sign, coef: coef, exp: exp}, locale, substitutions)
      when is_integer(coef) and exp > 0 do
    number = %Decimal{sign: sign, coef: coef * 10, exp: exp - 1}
    pluralize(number, locale, substitutions)
  end

  def pluralize(%Decimal{sign: sign, coef: coef, exp: exp}, locale, substitutions)
      when is_integer(coef) and exp < 0 and rem(coef, 10) == 0 do
    number = %Decimal{sign: sign, coef: Kernel.div(coef, 10), exp: exp + 1}
    pluralize(number, locale, substitutions)
  end

  def pluralize(%Decimal{} = number, %LanguageTag{} = locale, %{} = substitutions) do
    number
    |> Decimal.to_float()
    |> do_pluralize(locale, substitutions)
  end

  defp do_pluralize(number, %LanguageTag{} = locale, %{} = substitutions) do
    plural = plural_rule(number, locale)
    number = if (truncated = trunc(number)) == number, do: truncated, else: number
    substitutions[number] || substitutions[plural] || substitutions[@default_substitution]
  end

  @doc """
  Return the plural rules for a locale.

  ### Arguments

  * `locale` is a locale name string or atom, or a
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * A keyword list of `{category, parsed_rule}` pairs.

  """
  def plural_rules_for(%LanguageTag{cldr_locale_id: cldr_locale_id, language: language}) do
    plural_rules()[cldr_locale_id] || plural_rules()[language]
  end

  def plural_rules_for(locale_name) when is_atom(locale_name) or is_binary(locale_name) do
    with {:ok, parsed} <- LanguageTag.parse(to_string(locale_name)),
         {:ok, locale} <- LanguageTag.canonicalize(parsed) do
      plural_rules_for(locale)
    end
  end

  # ── Plural rule function: public API ──────────────────────────

  @doc """
  Return the plural category for a given number in a given locale.

  Returns which plural category (`:zero`, `:one`, `:two`, `:few`,
  `:many`, or `:other`) a given number belongs to within the
  context of a given locale.

  ### Arguments

  * `number` is any integer, float, or Decimal.

  * `locale` is a locale name string or a
    `t:Localize.LanguageTag.t/0`.

  * `rounding` is a positive integer specifying the number of
    fractional digits to consider. The default is `3`.

  ### Returns

  * A plural category atom.

  * `{:error, exception}` if no plural rules are available
    for the locale.

  ### Examples

      iex> Localize.Number.PluralRule.Ordinal.plural_rule(1, "en")
      :one

      iex> Localize.Number.PluralRule.Ordinal.plural_rule(2, "en")
      :two

      iex> Localize.Number.PluralRule.Ordinal.plural_rule(3, "en")
      :few

      iex> Localize.Number.PluralRule.Ordinal.plural_rule(4, "en")
      :other

  """
  @spec plural_rule(
          number() | Decimal.t(),
          String.t() | LanguageTag.t(),
          pos_integer()
        ) :: Localize.Number.PluralRule.plural_type() | {:error, Exception.t()}

  def plural_rule(number, locale, rounding \\ Math.default_rounding())

  def plural_rule(number, %LanguageTag{} = locale, rounding) when is_binary(number) do
    plural_rule(Decimal.new(number), locale, rounding)
  end

  # Plural rule for an integer
  def plural_rule(number, %LanguageTag{} = locale, _rounding) when is_integer(number) do
    n = abs(number)
    i = n
    v = 0
    w = 0
    f = 0
    t = 0
    e = 0
    do_plural_rule(locale, n, i, v, w, f, t, e)
  end

  # For a compact integer
  def plural_rule({number, e}, %LanguageTag{} = locale, _rounding) when is_integer(number) do
    n = abs(number)
    i = n
    v = 0
    w = 0
    f = 0
    t = 0
    do_plural_rule(locale, n, i, v, w, f, t, e)
  end

  # Plural rule for a float
  def plural_rule(number, %LanguageTag{} = locale, rounding)
      when is_float(number) and is_integer(rounding) and rounding > 0 do
    n = Float.round(abs(number), rounding)
    i = trunc(n)
    v = rounding
    t = fraction_as_integer(n - i, rounding)
    w = number_of_integer_digits(t)
    f = trunc(t * Math.power_of_10(v - w))
    e = 0
    do_plural_rule(locale, n, i, v, w, f, t, e)
  end

  # Plural rule for a compact float
  def plural_rule({number, e}, %LanguageTag{} = locale, rounding)
      when is_float(number) and is_integer(rounding) and rounding > 0 do
    n = Float.round(abs(number), rounding)
    i = trunc(n)
    v = rounding
    t = fraction_as_integer(n - i, rounding)
    w = number_of_integer_digits(t)
    f = trunc(t * Math.power_of_10(v - w))
    do_plural_rule(locale, n, i, v, w, f, t, e)
  end

  # Plural rule for a %Decimal{}
  def plural_rule(%Decimal{} = number, %LanguageTag{} = locale, rounding)
      when is_integer(rounding) and rounding > 0 do
    n = Decimal.abs(number)
    i = Decimal.round(n, 0, :floor)
    v = abs(n.exp)

    f =
      n
      |> Decimal.sub(i)
      |> Decimal.mult(Decimal.new(Math.power_of_10(v)))
      |> Decimal.round(0, :floor)
      |> Decimal.to_integer()

    t = remove_trailing_zeros(f)
    w = number_of_integer_digits(t)
    i = Decimal.to_integer(i)
    n = Math.to_float(n)
    e = 0

    do_plural_rule(locale, n, i, v, w, f, t, e)
  end

  # Plural rule for a compact %Decimal{}
  def plural_rule({%Decimal{} = number, e}, %LanguageTag{} = locale, rounding)
      when is_integer(rounding) and rounding > 0 do
    n = Decimal.abs(number)
    i = Decimal.round(n, 0, :floor)
    v = abs(n.exp)

    f =
      n
      |> Decimal.sub(i)
      |> Decimal.mult(Decimal.new(Math.power_of_10(v)))
      |> Decimal.round(0, :floor)
      |> Decimal.to_integer()

    t = remove_trailing_zeros(f)
    w = number_of_integer_digits(t)
    i = Decimal.to_integer(i)
    n = Math.to_float(n)

    do_plural_rule(locale, n, i, v, w, f, t, e)
  end

  # Fallback: parse locale string and retry
  def plural_rule(number, locale_name, rounding)
      when is_binary(locale_name) or is_atom(locale_name) do
    with {:ok, parsed} <- LanguageTag.parse(to_string(locale_name)),
         {:ok, locale} <- LanguageTag.canonicalize(parsed) do
      plural_rule(number, locale, rounding)
    end
  end

  # ── Generated plural rule functions ───────────────────────────

  @dialyzer {:nowarn_function, [do_plural_rule: 8]}

  @spec do_plural_rule(
          LanguageTag.t(),
          number(),
          Localize.Number.PluralRule.operand(),
          Localize.Number.PluralRule.operand(),
          Localize.Number.PluralRule.operand(),
          Localize.Number.PluralRule.operand(),
          [integer(), ...] | integer(),
          number()
        ) :: :zero | :one | :two | :few | :many | :other | {:error, Exception.t()}

  for locale_name <- @rules |> Map.keys() |> Enum.sort() do
    function_body =
      @rules
      |> Map.get(locale_name)
      |> rules_to_condition_statement(__MODULE__)

    defp do_plural_rule(
           %LanguageTag{cldr_locale_id: unquote(locale_name)},
           n,
           i,
           v,
           w,
           f,
           t,
           e
         ) do
      _ = {n, i, v, w, f, t, e}
      unquote(function_body)
    end
  end

  # If the locale doesn't have a plural rule, try the language
  defp do_plural_rule(%LanguageTag{} = language_tag, n, i, v, w, f, t, e) do
    language_atom = String.to_atom(to_string(language_tag.language))

    if language_atom == language_tag.cldr_locale_id do
      {:error,
       Localize.UnknownPluralRulesError.exception(
         locale_id: language_tag.cldr_locale_id,
         type: :ordinal
       )}
    else
      language_tag
      |> Map.put(:cldr_locale_id, language_atom)
      |> do_plural_rule(n, i, v, w, f, t, e)
    end
  end
end
