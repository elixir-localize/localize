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
  alias Localize.SupplementalData

  # Load rules at compile time for function generation only.
  # The attribute is deleted after generation so the raw data
  # is not embedded in the BEAM file.
  #
  # Declaring the ETF as an external resource is what makes a CLDR data
  # refresh recompile this module. Without it `mix` sees no edge from the
  # data to the BEAM, so a regenerated `plural_rules_ordinal.etf` leaves
  # last release's rules compiled in — and because the sample tests are
  # themselves generated from the fresh data, the mismatch surfaces as a
  # wall of failures that reads like a CLDR regression rather than a stale
  # build.
  @external_resource Application.app_dir(
                       :localize,
                       "priv/localize/supplemental_data/plural_rules_ordinal.etf"
                     )

  @rules_at_compile Localize.Number.PluralRule.Loader.load_plural_rules(:ordinal)

  # The locales with rules of their own, as a map a guard can test. A
  # locale whose data is the root's takes its language's rules where CLDR
  # has them: `ars`, `bal` and `ny` have plural rules but no main locale.
  @rule_locales Map.new(Map.keys(@rules_at_compile), &{&1, true})

  @default_substitution :other

  @doc """
  Returns the locale names for which ordinal plural rules
  are defined.

  ### Returns

  * A sorted list of locale name atoms.

  ### Examples

      iex> :en in Localize.Number.PluralRule.Ordinal.available_locale_names()
      true

  """
  @spec available_locale_names :: [atom(), ...]
  def available_locale_names do
    SupplementalData.plural_rules_locales(:ordinal)
  end

  @doc """
  Returns all the ordinal plural rules defined in CLDR.

  ### Returns

  * A map of locale names to their parsed plural rule definitions.

  ### Examples

      iex> rules = Localize.Number.PluralRule.Ordinal.plural_rules()
      iex> rules[:en] |> Keyword.keys() |> Enum.sort()
      [:few, :one, :other, :two]

  """
  @spec plural_rules() :: %{optional(atom()) => Keyword.t()}
  def plural_rules do
    SupplementalData.plural_rules(:ordinal)
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

  * `{:error, exception}` if the locale, the number or the
    substitutions are not valid.

  ### Examples

      iex> Localize.Number.PluralRule.Ordinal.pluralize(1, "en", %{one: "st", two: "nd", few: "rd", other: "th"})
      "st"

      iex> Localize.Number.PluralRule.Ordinal.pluralize(2, "en", %{one: "st", two: "nd", few: "rd", other: "th"})
      "nd"

  """

  @spec pluralize(
          number() | Decimal.t(),
          atom() | String.t() | LanguageTag.t(),
          map()
        ) :: term()
  def pluralize(number, locale_name, substitutions)
      when is_atom(locale_name) or is_binary(locale_name) do
    with {:ok, language_tag} <- Localize.validate_locale(locale_name) do
      pluralize(number, language_tag, substitutions)
    end
  end

  def pluralize(number, %LanguageTag{} = locale, %{} = substitutions)
      when is_number(number) do
    do_pluralize(number, locale, substitutions)
  end

  def pluralize(
        %Decimal{sign: _sign, coef: coef, exp: 0} = number,
        %LanguageTag{} = locale,
        %{} = substitutions
      )
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

  # NaN and ±Infinity select `other`, as `plural_rule/3` does, and are no
  # exact value; `Decimal.to_float/1` below would raise on them.
  def pluralize(%Decimal{coef: coef}, %LanguageTag{}, %{} = substitutions)
      when coef in [:NaN, :inf] do
    substitutions[:other] || substitutions[@default_substitution]
  end

  def pluralize(%Decimal{} = number, %LanguageTag{} = locale, %{} = substitutions) do
    number
    |> Decimal.to_float()
    |> do_pluralize(locale, substitutions)
  end

  def pluralize(_number, %LanguageTag{}, substitutions) when not is_map(substitutions) do
    {:error,
     Localize.Utils.Helpers.invalid_value(substitutions, "a map of plural categories to values")}
  end

  def pluralize(number, %LanguageTag{}, _substitutions),
    do: {:error, Localize.Utils.Helpers.invalid_value(number, "a number or a Decimal")}

  def pluralize(_number, locale, _substitutions),
    do: {:error, Localize.InvalidLocaleError.exception(locale_id: locale)}

  defp do_pluralize(number, %LanguageTag{} = locale, %{} = substitutions) do
    plural = plural_rule(number, locale)
    truncated = trunc(number)
    number = if truncated == number, do: truncated, else: number
    substitutions[number] || substitutions[plural] || substitutions[@default_substitution]
  end

  @doc """
  Return the plural rules for a locale.

  ### Arguments

  * `locale` is a locale name string or atom, or a
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * A keyword list of `{category, parsed_rule}` pairs, or `nil` if
    the locale has no ordinal plural rules.

  * `{:error, exception}` if the locale identifier is invalid.

  ### Examples

      iex> Localize.Number.PluralRule.Ordinal.plural_rules_for(:en) |> Keyword.keys() |> Enum.sort()
      [:few, :one, :other, :two]

  """
  @spec plural_rules_for(atom() | String.t() | LanguageTag.t()) ::
          Keyword.t() | nil | {:error, Exception.t()}
  def plural_rules_for(%LanguageTag{} = language_tag) do
    plural_rules()[rules_locale(language_tag)]
  end

  def plural_rules_for(locale_name) when is_atom(locale_name) or is_binary(locale_name) do
    with {:ok, locale} <- Localize.validate_locale(locale_name) do
      plural_rules_for(locale)
    end
  end

  def plural_rules_for(locale),
    do: {:error, Localize.InvalidLocaleError.exception(locale_id: locale)}

  # The locale whose rules apply. TR35 gives plural rules their own
  # inheritance, by truncation: the CLDR locale where it has rules, else
  # its language. A locale whose data is the root's still takes its
  # language's rules where CLDR has them (`ars`, `bal`, `ny`); the root
  # itself, asked for as `und`, takes the root's, although its validated
  # tag carries the likely language `en`.
  defp rules_locale(%LanguageTag{cldr_locale_id: locale_id} = language_tag) do
    cond do
      locale_id != :und and is_map_key(@rule_locales, locale_id) -> locale_id
      locale_id == :und and requests_root?(language_tag) -> :und
      is_map_key(@rule_locales, language_tag.language) -> language_tag.language
      true -> locale_id
    end
  end

  defp requests_root?(%LanguageTag{canonical_locale_id: "und"}) do
    true
  end

  defp requests_root?(%LanguageTag{canonical_locale_id: "und-" <> _extensions}) do
    true
  end

  defp requests_root?(%LanguageTag{}) do
    false
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

  * `{:error, exception}` if the number, locale or rounding is
    not valid, or no plural rules are available for the locale.

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
    case Decimal.parse(number) do
      {decimal, ""} -> plural_rule(decimal, locale, rounding)
      _other -> {:error, Localize.Utils.Helpers.invalid_value(number, "a number string")}
    end
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

  # For a compact value `{mantissa, exponent}` — the "1.2c6" notation
  # used by compact decimal formatting. Per TR35 the n, i, f, t, v and
  # w operands are computed *after* shifting the decimal point by the
  # exponent (1.2c6 has the operands of 1200000), and the exponent
  # becomes the `e` operand. The shift is exact: the mantissa is
  # converted to `Decimal` and the exponent added to `Decimal.exp`.
  def plural_rule({number, e}, %LanguageTag{} = locale, rounding)
      when is_integer(number) and is_integer(e) and e >= 0 do
    plural_rule_with_exponent(Decimal.new(number), e, locale, rounding)
  end

  def plural_rule({number, e}, %LanguageTag{} = locale, rounding)
      when is_float(number) and is_integer(e) and e >= 0 do
    plural_rule_with_exponent(Decimal.from_float(number), e, locale, rounding)
  end

  # NaN and ±Infinity have no TR35 plural operands, and TR35 does not
  # say how to select for them. ICU and ECMA-402 (`Intl.PluralRules`)
  # select `other`, so this does too.
  def plural_rule({%Decimal{coef: coef}, e}, %LanguageTag{}, rounding)
      when coef in [:NaN, :inf] and is_integer(e) and e >= 0 and is_integer(rounding) and
             rounding > 0 do
    :other
  end

  def plural_rule(%Decimal{coef: coef}, %LanguageTag{}, rounding)
      when coef in [:NaN, :inf] and is_integer(rounding) and rounding > 0 do
    :other
  end

  def plural_rule({%Decimal{} = number, e}, %LanguageTag{} = locale, rounding)
      when is_integer(e) and e >= 0 do
    plural_rule_with_exponent(number, e, locale, rounding)
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

  # Plural rule for a %Decimal{}
  def plural_rule(%Decimal{} = number, %LanguageTag{} = locale, rounding)
      when is_integer(rounding) and rounding > 0 do
    {n, i, v, w, f, t} = decimal_operands(number)
    do_plural_rule(locale, n, i, v, w, f, t, 0)
  end

  # Fallback: validate the locale identifier and retry
  def plural_rule(number, locale_name, rounding)
      when is_binary(locale_name) or is_atom(locale_name) do
    with {:ok, locale} <- Localize.validate_locale(locale_name) do
      plural_rule(number, locale, rounding)
    end
  end

  def plural_rule(number, %LanguageTag{}, rounding)
      when (is_float(number) or is_struct(number, Decimal)) and
             not (is_integer(rounding) and rounding > 0),
      do: {:error, Localize.Utils.Helpers.invalid_value(rounding, "a positive integer")}

  def plural_rule(number, %LanguageTag{}, _rounding) do
    {:error,
     Localize.Utils.Helpers.invalid_value(number, "a number, a Decimal or a number string")}
  end

  def plural_rule(_number, locale, _rounding),
    do: {:error, Localize.InvalidLocaleError.exception(locale_id: locale)}

  defp plural_rule_with_exponent(%Decimal{} = number, e, locale, _rounding) do
    shifted = %{number | exp: number.exp + e}
    {n, i, v, w, f, t} = decimal_operands(shifted)
    do_plural_rule(locale, n, i, v, w, f, t, e)
  end

  # Computes the TR35 plural operands from a Decimal, by integer arithmetic
  # on its coefficient and exponent. The Decimal library's own arithmetic
  # read its context on each of seven calls and cost a compact number most
  # of its formatting (#67):
  #
  # * n — absolute value of the source (integer and decimals).
  # * i — integer digits of n.
  # * v — count of visible fraction digits, with trailing zeros. Only a
  #   negative Decimal exponent contributes fraction digits; a positive
  #   exponent (e.g. `12e5`) is an integer with v = 0.
  # * w — count of visible fraction digits, without trailing zeros.
  # * f — visible fraction digits as an integer, with trailing zeros.
  # * t — visible fraction digits as an integer, without trailing zeros.
  defp decimal_operands(%Decimal{coef: coef, exp: exp} = number) do
    {i, v, f} = integer_and_fraction(coef, exp)
    t = remove_trailing_zeros(f)
    w = number_of_integer_digits(t)

    {abs(Math.to_float(number)), i, v, w, f, t}
  end

  # A positive exponent is an integer with no fraction digits; a negative
  # one has as many as its magnitude, which split the coefficient into the
  # integer digits and the fraction digits with their trailing zeros.
  defp integer_and_fraction(coef, exp) when exp >= 0 do
    {coef * Math.power_of_10(exp), 0, 0}
  end

  defp integer_and_fraction(coef, exp) do
    scale = Math.power_of_10(-exp)
    {div(coef, scale), -exp, rem(coef, scale)}
  end

  # ── Generated plural rule functions ───────────────────────────

  @dialyzer {:nowarn_function, [do_plural_rule: 8, locale_plural_rule: 8]}

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

  defp do_plural_rule(%LanguageTag{} = language_tag, n, i, v, w, f, t, e) do
    language_tag
    |> rules_locale()
    |> locale_plural_rule(n, i, v, w, f, t, e)
  end

  for locale_name <- @rules_at_compile |> Map.keys() |> Enum.sort() do
    function_body =
      @rules_at_compile
      |> Map.get(locale_name)
      |> rules_to_condition_statement(__MODULE__)

    defp locale_plural_rule(
           unquote(locale_name),
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

  Module.delete_attribute(__MODULE__, :rules_at_compile)

  defp locale_plural_rule(locale_id, _n, _i, _v, _w, _f, _t, _e) do
    {:error, Localize.UnknownPluralRulesError.exception(locale_id: locale_id, type: :ordinal)}
  end
end
