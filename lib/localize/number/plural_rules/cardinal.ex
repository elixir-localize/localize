defmodule Localize.Number.PluralRule.Cardinal do
  @moduledoc """
  Implements cardinal plural rules for numbers.

  Cardinal plural rules are used for counting quantities
  (e.g., "1 item", "2 items", "5 items"). Each locale has
  its own set of rules that classify a number into one of
  the plural categories: `:zero`, `:one`, `:two`, `:few`,
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
  @rules_at_compile Localize.Number.PluralRule.Loader.load_plural_rules(:cardinal)

  @doc """
  Returns the locale names for which cardinal plural rules
  are defined.

  ### Returns

  * A sorted list of locale name atoms.

  ### Examples

      iex> :en in Localize.Number.PluralRule.Cardinal.available_locale_names()
      true

  """
  @spec available_locale_names :: [atom(), ...]
  def available_locale_names do
    SupplementalData.plural_rules_locales(:cardinal)
  end

  @doc """
  Returns all the cardinal plural rules defined in CLDR.

  ### Returns

  * A map of locale names to their parsed plural rule definitions.

  ### Examples

      iex> rules = Localize.Number.PluralRule.Cardinal.plural_rules()
      iex> rules[:en] |> Keyword.keys() |> Enum.sort()
      [:one, :other]

  """
  @spec plural_rules() :: %{optional(atom()) => Keyword.t()}
  def plural_rules do
    SupplementalData.plural_rules(:cardinal)
  end

  @doc """
  Pluralize a number using cardinal plural rules and a
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

      iex> Localize.Number.PluralRule.Cardinal.pluralize(1, "en", %{one: "one", other: "other"})
      "one"

      iex> Localize.Number.PluralRule.Cardinal.pluralize(2, "en", %{one: "one", other: "other"})
      "other"

  """
  @default_substitution :other

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
    the locale has no cardinal plural rules.

  * `{:error, exception}` if the locale identifier is invalid.

  ### Examples

      iex> Localize.Number.PluralRule.Cardinal.plural_rules_for(:en) |> Keyword.keys() |> Enum.sort()
      [:one, :other]

  """
  @spec plural_rules_for(atom() | String.t() | LanguageTag.t()) ::
          Keyword.t() | nil | {:error, Exception.t()}
  def plural_rules_for(%LanguageTag{cldr_locale_id: cldr_locale_id, language: language}) do
    plural_rules()[cldr_locale_id] || plural_rules()[language]
  end

  def plural_rules_for(locale_name) when is_atom(locale_name) or is_binary(locale_name) do
    with {:ok, locale} <- Localize.validate_locale(locale_name) do
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

      iex> Localize.Number.PluralRule.Cardinal.plural_rule(0, "en")
      :other

      iex> Localize.Number.PluralRule.Cardinal.plural_rule(1, "en")
      :one

      iex> Localize.Number.PluralRule.Cardinal.plural_rule(2, "en")
      :other

  """
  @spec plural_rule(
          number() | Decimal.t(),
          atom() | String.t() | LanguageTag.t(),
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

  defp plural_rule_with_exponent(%Decimal{} = number, e, locale, _rounding) do
    shifted = %{number | exp: number.exp + e}
    {n, i, v, w, f, t} = decimal_operands(shifted)
    do_plural_rule(locale, n, i, v, w, f, t, e)
  end

  # Computes the TR35 plural operands from a Decimal:
  #
  # * n — absolute value of the source (integer and decimals).
  # * i — integer digits of n.
  # * v — count of visible fraction digits, with trailing zeros. Only a
  #   negative Decimal exponent contributes fraction digits; a positive
  #   exponent (e.g. `12e5`) is an integer with v = 0.
  # * w — count of visible fraction digits, without trailing zeros.
  # * f — visible fraction digits as an integer, with trailing zeros.
  # * t — visible fraction digits as an integer, without trailing zeros.
  defp decimal_operands(%Decimal{} = number) do
    n = Decimal.abs(number)
    i = Decimal.round(n, 0, :floor)
    v = max(0, -n.exp)

    f =
      n
      |> Decimal.sub(i)
      |> Decimal.mult(Decimal.new(Math.power_of_10(v)))
      |> Decimal.round(0, :floor)
      |> Decimal.to_integer()

    t = remove_trailing_zeros(f)
    w = number_of_integer_digits(t)

    {Math.to_float(n), Decimal.to_integer(i), v, w, f, t}
  end

  # ── Generated plural rule functions ───────────────────────────

  # Silence warnings since the success typing of do_plural_rule
  # will depend on the locale used.
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

  # Generate per-locale do_plural_rule/8 functions from the CLDR data
  for locale_name <- @rules_at_compile |> Map.keys() |> Enum.sort() do
    function_body =
      @rules_at_compile
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
      # silence unused variable warnings
      _ = {n, i, v, w, f, t, e}
      unquote(function_body)
    end
  end

  Module.delete_attribute(__MODULE__, :rules_at_compile)

  # If the locale doesn't have a plural rule, try the language
  defp do_plural_rule(%LanguageTag{} = language_tag, n, i, v, w, f, t, e) do
    # `language_tag.language` is already a validated atom (or nil) after
    # `LanguageTag.parse/1`. The previous `String.to_atom(to_string(...))`
    # round-trip was a no-op for atoms but would atomise `""` from a nil
    # language; using the field directly avoids both.
    language_atom = language_tag.language

    if language_atom == language_tag.cldr_locale_id do
      {:error,
       Localize.UnknownPluralRulesError.exception(
         locale_id: language_tag.cldr_locale_id,
         type: :cardinal
       )}
    else
      language_tag
      |> Map.put(:cldr_locale_id, language_atom)
      |> do_plural_rule(n, i, v, w, f, t, e)
    end
  end
end
