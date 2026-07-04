defmodule Localize.Number.PluralRule do
  @moduledoc """
  Defines plural rule modules for cardinal and ordinal number
  categories according to the CLDR plural rules specification.

  At compile time, this module generates two child modules:

  * `Localize.Number.PluralRule.Cardinal` — implements cardinal
    plural rules (used for counting: "1 item", "2 items").

  * `Localize.Number.PluralRule.Ordinal` — implements ordinal
    plural rules (used for ordering: "1st", "2nd", "3rd").

  Each generated module contains per-locale `plural_rule/2`
  functions that classify a number into one of the CLDR plural
  categories: `:zero`, `:one`, `:two`, `:few`, `:many`, or
  `:other`.

  """

  alias Localize.LanguageTag

  @type operand :: any()

  @typedoc """
  The plural categories into which a number can be classified.

  """
  @type plural_type :: :zero | :one | :two | :few | :many | :other

  @typedoc """
  A plural rule definition before compilation.

  """
  @type plural_rule :: Keyword.t()

  @plural_types [:zero, :one, :two, :few, :many, :other]

  @doc """
  Returns the list of possible plural categories.

  ### Returns

  * A list of plural type atoms.

  ### Examples

      iex> Localize.Number.PluralRule.known_plural_types()
      [:zero, :one, :two, :few, :many, :other]

  """
  @spec known_plural_types :: [plural_type(), ...]
  def known_plural_types do
    @plural_types
  end

  @doc """
  Returns the plural category for a given number.

  ### Arguments

  * `number` is an integer, float, or Decimal number.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is any locale identifier string or a
    `t:Localize.LanguageTag.t/0`. The default is `"en"`.

  * `:type` is either `:cardinal` or `:ordinal`.
    The default is `:cardinal`.

  ### Returns

  * A plural category atom: `:zero`, `:one`, `:two`, `:few`,
    `:many`, or `:other`.

  * `{:error, exception}` if no plural rules are available
    for the given locale.

  ### Examples

      iex> Localize.Number.PluralRule.plural_type(1, locale: "en")
      :one

      iex> Localize.Number.PluralRule.plural_type(2, locale: "en")
      :other

      iex> Localize.Number.PluralRule.plural_type(1, locale: "en", type: :ordinal)
      :one

      iex> Localize.Number.PluralRule.plural_type(2, locale: "en", type: :ordinal)
      :two

  """
  @spec plural_type(number() | Decimal.t(), Keyword.t()) ::
          plural_type() | {:error, Exception.t()}
  @dialyzer {:nowarn_function, plural_type: 2}
  def plural_type(number, options \\ []) do
    case Localize.Backend.resolve(options) do
      :nif ->
        locale = Keyword.get(options, :locale, Localize.get_locale())
        type = Keyword.get(options, :type, :cardinal)

        # The NIF returns `{:ok, plural_type}` — unwrap it so both
        # backends return a bare plural category atom on success,
        # as documented by the `@spec`. Error tuples pass through.
        with {:ok, locale_string} <- validated_locale_string(locale),
             {:ok, plural} <- Localize.Nif.plural_rule(number, locale_string, type) do
          plural
        end

      :elixir ->
        plural_type_elixir(number, options)
    end
  end

  # The NIF backend validates the locale through the same canonical
  # path as the Elixir backend (`Localize.validate_locale/1`) and hands
  # ICU the canonical BCP 47 string, so both backends resolve aliases,
  # likely subtags and `-u-` extensions identically.
  defp validated_locale_string(locale) do
    with {:ok, language_tag} <- Localize.validate_locale(locale) do
      {:ok, LanguageTag.to_string(language_tag)}
    end
  end

  defp plural_type_elixir(number, options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    type = Keyword.get(options, :type, :cardinal)

    locale =
      case Localize.validate_locale(locale) do
        {:ok, language_tag} -> language_tag
        {:error, _} -> nil
      end

    if locale do
      module =
        case type do
          :cardinal -> Localize.Number.PluralRule.Cardinal
          :ordinal -> Localize.Number.PluralRule.Ordinal
        end

      module.plural_rule(number, locale)
    else
      {:error,
       Localize.UnknownPluralRulesError.exception(
         locale_id: Keyword.get(options, :locale, Localize.get_locale()),
         type: type
       )}
    end
  end

  # ── Compile-time data loading ─────────────────────────────────
  #
  # Moved to `Localize.Number.PluralRule.Loader` so that the
  # `Cardinal` and `Ordinal` modules can compile-time depend on a
  # leaf module without inheriting this module's runtime back-edges
  # into the broader compile-connected cycle.
end
