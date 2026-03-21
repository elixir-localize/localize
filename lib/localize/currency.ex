defmodule Localize.Currency do
  @moduledoc """
  Defines a currency structure and functions to manage currency
  codes, validate currencies, and retrieve currency metadata.

  Currency data is derived from the Unicode CLDR repository and
  includes all ISO 4217 currency codes, territory-to-currency
  mappings, and support for custom (private use) currencies.

  Locale-specific currency data (display names, pluralized names,
  symbols) will be implemented in a future release. Functions that
  require locale data are currently stubs that return
  `{:error, :not_yet_implemented}`.

  """

  alias Localize.SupplementalData

  @type currency_code :: atom()

  @type currency_status :: :all | :current | :historic | :tender | :unannotated | :private

  @type filter :: list(currency_status() | currency_code()) | currency_status() | currency_code()

  @type territory :: atom() | String.t()

  @type t :: %__MODULE__{
          code: currency_code(),
          alt_code: currency_code(),
          name: String.t(),
          tender: boolean(),
          symbol: String.t(),
          digits: non_neg_integer(),
          rounding: non_neg_integer(),
          narrow_symbol: String.t() | nil,
          cash_digits: non_neg_integer(),
          cash_rounding: non_neg_integer(),
          iso_digits: non_neg_integer(),
          decimal_separator: String.t() | nil,
          grouping_separator: String.t() | nil,
          count: map() | nil,
          from: Date.t() | nil,
          to: Date.t() | nil
        }

  defstruct code: nil,
            alt_code: nil,
            name: "",
            symbol: "",
            narrow_symbol: nil,
            digits: 0,
            rounding: 0,
            cash_digits: 0,
            cash_rounding: 0,
            iso_digits: 0,
            decimal_separator: nil,
            grouping_separator: nil,
            tender: false,
            count: nil,
            from: nil,
            to: nil

  @valid_custom_currency_code ~r/^[A-Z][A-Z0-9]{3,10}$/
  @valid_private_currency_code ~r/^X[A-Z]{2}$/

  # ── Known currency codes (loaded from ETF at compile time) ───

  @currency_codes SupplementalData.currency_codes()
  @territory_currencies SupplementalData.territory_currencies()

  # ── Creating custom currencies ───────────────────────────────

  @doc """
  Creates a new custom currency and stores it.

  Custom currency codes must be either ISO 4217 private use codes
  (matching `X[A-Z]{2}`) or extended codes with 4-11 uppercase
  alphanumeric characters. The code must not already be defined.

  ### Arguments

  * `currency_code` is an atom or string currency code.

  * `options` is a keyword list of currency attributes.

  ### Options

  * `:name` is the name of the currency. Required.

  * `:digits` is the precision of the currency. Required.

  * `:symbol` is the currency symbol. Optional.

  * `:narrow_symbol` is an alternative narrow symbol. Optional.

  * `:round_nearest` is the rounding precision such as `0.05`. Optional.

  * `:alt_code` is an alternative currency code for application use. Optional.

  * `:cash_digits` is the precision when used as cash. Optional.

  * `:cash_round_nearest` is the cash rounding precision. Optional.

  ### Returns

  * `{:ok, Localize.Currency.t()}` on success.

  * `{:error, exception}` if the code is invalid or already defined.

  ### Examples

      iex> Localize.Currency.new(:XAC, name: "XAC currency", digits: 0)
      {:ok,
       %Localize.Currency{
        code: :XAC,
        alt_code: :XAC,
        name: "XAC currency",
        symbol: "XAC",
        narrow_symbol: nil,
        digits: 0,
        rounding: 0,
        cash_digits: 0,
        cash_rounding: nil,
        iso_digits: 0,
        decimal_separator: nil,
        grouping_separator: nil,
        tender: false,
        count: %{other: "XAC currency"},
        from: nil,
        to: nil
      }}

  """
  @spec new(atom() | String.t(), Keyword.t()) ::
          {:ok, t()} | {:error, Exception.t()}
  def new(currency_code, options \\ []) do
    with {:ok, currency_code} <- validate_new_currency(currency_code),
         {:ok, options} <- validate_options(currency_code, options) do
      currency = struct(__MODULE__, [{:code, currency_code} | options])
      Localize.Currency.Store.put(currency)
    end
  end

  # ── Currency validation ──────────────────────────────────────

  @doc """
  Validates a currency code and returns its canonical atom form.

  Checks both ISO 4217 codes and registered custom currencies.

  ### Arguments

  * `currency_code` is an atom or string currency code.

  ### Returns

  * `{:ok, currency_code}` where `currency_code` is an atom.

  * `{:error, Localize.UnknownCurrencyError.t()}` if the code
    is not known.

  ### Examples

      iex> Localize.Currency.validate_currency("AUD")
      {:ok, :AUD}

      iex> Localize.Currency.validate_currency(:USD)
      {:ok, :USD}

  """
  @spec validate_currency(atom() | String.t()) ::
          {:ok, currency_code()} | {:error, Exception.t()}
  def validate_currency(currency_code) when is_binary(currency_code) do
    currency_code
    |> String.upcase()
    |> String.to_atom()
    |> validate_currency()
  end

  def validate_currency(currency_code) when is_atom(currency_code) do
    if currency_code in known_currency_codes() do
      {:ok, currency_code}
    else
      {:error, Localize.UnknownCurrencyError.exception(currency: currency_code)}
    end
  end

  @doc """
  Validates that a currency code is available for defining
  as a new custom currency.

  ### Arguments

  * `currency_code` is an atom or string currency code.

  ### Returns

  * `{:ok, currency_code}` if the code is valid and not yet defined.

  * `{:error, exception}` if the code is already defined or invalid.

  ### Examples

      iex> Localize.Currency.validate_new_currency(:XAD)
      {:ok, :XAD}

  """
  @spec validate_new_currency(atom() | String.t()) ::
          {:ok, currency_code()} | {:error, Exception.t()}
  def validate_new_currency(currency_code) do
    canonical_code = canonicalize_currency_code(currency_code)

    if canonical_code in @currency_codes do
      {:error, Localize.CurrencyAlreadyDefinedError.exception(currency: canonical_code)}
    else
      case validate_custom_currency_code(currency_code) do
        {:ok, code} ->
          if code in Localize.Currency.Store.codes() do
            {:error, Localize.CurrencyAlreadyDefinedError.exception(currency: code)}
          else
            {:ok, code}
          end

        {:error, _} = error ->
          error
      end
    end
  end

  defp canonicalize_currency_code(code) when is_atom(code), do: code

  defp canonicalize_currency_code(code) when is_binary(code) do
    code |> String.upcase() |> String.to_atom()
  end

  # ── Known currencies ─────────────────────────────────────────

  @doc """
  Returns a list of all known currency codes.

  This includes all ISO 4217 codes plus any custom currencies
  that have been registered.

  ### Returns

  * A list of atom currency codes.

  ### Examples

      iex> codes = Localize.Currency.known_currency_codes()
      iex> :USD in codes
      true

  """
  @spec known_currency_codes() :: [currency_code()]
  def known_currency_codes do
    @currency_codes ++ Localize.Currency.Store.codes()
  end

  @doc """
  Returns whether the given currency code is known.

  ### Arguments

  * `currency_code` is an atom or string currency code.

  ### Returns

  * `true` or `false`.

  ### Examples

      iex> Localize.Currency.known_currency_code?(:USD)
      true

      iex> Localize.Currency.known_currency_code?("GGG")
      false

  """
  @spec known_currency_code?(atom() | String.t()) :: boolean()
  def known_currency_code?(currency_code) do
    case validate_currency(currency_code) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Returns a list of all custom currency codes.

  ### Returns

  * A list of atom currency codes that were defined with `new/2`.

  """
  @spec private_currency_codes() :: [atom()]
  def private_currency_codes do
    Localize.Currency.Store.codes()
  end

  @doc """
  Returns a map of all custom currencies.

  ### Returns

  * A map of `%{currency_code => Localize.Currency.t()}`.

  """
  @spec private_currencies() :: %{currency_code() => t()}
  def private_currencies do
    Localize.Currency.Store.all()
  end

  # ── Territory currency functions ─────────────────────────────

  @doc """
  Returns a map of all territory codes to their currency history.

  Each territory maps to a map of currency codes with date ranges
  indicating when each currency was in use.

  ### Returns

  * A map of `%{territory_code => %{currency_code => date_info}}`.

  ### Examples

      iex> currencies = Localize.Currency.territory_currencies()
      iex> us = Map.get(currencies, :US)
      iex> Map.has_key?(us, :USD)
      true

  """
  @spec territory_currencies() :: %{atom() => map()}
  def territory_currencies do
    @territory_currencies
  end

  @doc """
  Returns the currency history for a specific territory.

  ### Arguments

  * `territory` is a territory code atom or string (e.g., `:US` or `"US"`).

  ### Returns

  * `{:ok, currency_map}` with currency codes and date ranges.

  * `{:error, Localize.UnknownCurrencyError.t()}` if no currencies
    are found for the territory.

  ### Examples

      iex> {:ok, currencies} = Localize.Currency.territory_currencies(:US)
      iex> Map.has_key?(currencies, :USD)
      true

  """
  @spec territory_currencies(territory()) ::
          {:ok, map()} | {:error, Exception.t()}
  def territory_currencies(territory) when is_binary(territory) do
    territory
    |> String.upcase()
    |> String.to_atom()
    |> territory_currencies()
  end

  def territory_currencies(territory) when is_atom(territory) do
    case Map.fetch(territory_currencies(), territory) do
      {:ok, currencies} ->
        {:ok, currencies}

      :error ->
        {:error,
         Localize.UnknownCurrencyError.exception(
           currency: "No currencies for #{inspect(territory)} were found"
         )}
    end
  end

  @doc """
  Returns the current currency for a given territory.

  The current currency is the one with no `:to` end date and
  where `:tender` is not `false`.

  ### Arguments

  * `territory` is a territory code atom or string.

  ### Returns

  * A currency code atom, or `nil` if no current currency exists.

  ### Examples

      iex> Localize.Currency.current_currency_for_territory(:US)
      :USD

      iex> Localize.Currency.current_currency_for_territory(:AU)
      :AUD

  """
  @spec current_currency_for_territory(atom() | String.t()) ::
          currency_code() | nil
  def current_currency_for_territory(territory) when is_binary(territory) do
    territory
    |> String.upcase()
    |> String.to_atom()
    |> current_currency_for_territory()
  end

  def current_currency_for_territory(territory) when is_atom(territory) do
    case territory_currencies(territory) do
      {:ok, history} ->
        history
        |> Enum.find(fn {_currency, info} ->
          Map.has_key?(info, :from) &&
            !Map.has_key?(info, :to) &&
            Map.get(info, :tender, true) != false
        end)
        |> case do
          {currency, _info} -> currency
          nil -> nil
        end

      {:error, _} ->
        nil
    end
  end

  @doc """
  Returns a map of territory codes to their current currency.

  Territories with no current currency are excluded.

  ### Returns

  * A map of `%{territory_code => currency_code}`.

  ### Examples

      iex> map = Localize.Currency.current_territory_currencies()
      iex> Map.get(map, :US)
      :USD

  """
  @spec current_territory_currencies() :: %{atom() => currency_code()}
  def current_territory_currencies do
    territory_currencies()
    |> Enum.reject(fn {territory, _} -> territory == :ZZ end)
    |> Enum.map(fn {territory, _} ->
      {territory, current_currency_for_territory(territory)}
    end)
    |> Enum.reject(fn {_, currency} -> is_nil(currency) end)
    |> Map.new()
  end

  # ── Locale-based currency functions ──────────────────────────

  @doc """
  Returns the effective currency for a given language tag.

  If the language tag has a `cu` Unicode extension key set,
  that currency is returned. Otherwise, the current currency
  for the tag's territory is returned.

  ### Arguments

  * `locale` is a `t:Localize.LanguageTag.t/0` struct.

  ### Returns

  * A currency code atom.

  ### Examples

      iex> {:ok, tag} = Localize.LanguageTag.parse("en-US")
      iex> Localize.Currency.currency_from_locale(tag)
      :USD

  """
  @spec currency_from_locale(Localize.LanguageTag.t()) :: currency_code() | nil
  def currency_from_locale(%Localize.LanguageTag{locale: %{cu: nil}} = locale) do
    current_currency_from_locale(locale)
  end

  def currency_from_locale(%Localize.LanguageTag{locale: %{cu: currency}}) do
    currency
  end

  def currency_from_locale(%Localize.LanguageTag{} = locale) do
    current_currency_from_locale(locale)
  end

  @doc """
  Returns the effective currency format for a given language tag.

  If the language tag has a `cf` Unicode extension key set to
  `:account`, returns `:accounting`. Otherwise returns `:currency`.

  ### Arguments

  * `locale` is a `t:Localize.LanguageTag.t/0` struct.

  ### Returns

  * `:currency` or `:accounting`.

  ### Examples

      iex> {:ok, tag} = Localize.LanguageTag.parse("en-US")
      iex> Localize.Currency.currency_format_from_locale(tag)
      :currency

  """
  @spec currency_format_from_locale(Localize.LanguageTag.t()) ::
          :currency | :accounting
  def currency_format_from_locale(%Localize.LanguageTag{locale: %{cf: :account}}) do
    :accounting
  end

  def currency_format_from_locale(%Localize.LanguageTag{}) do
    :currency
  end

  @doc """
  Returns the current currency for a locale's territory.

  This function does not consider the `U` extension parameter `cu`.
  Use `currency_from_locale/1` to get the effective currency
  including overrides.

  ### Arguments

  * `locale` is a `t:Localize.LanguageTag.t/0` struct.

  ### Returns

  * A currency code atom, or `nil`.

  """
  @spec current_currency_from_locale(Localize.LanguageTag.t()) ::
          currency_code() | nil
  def current_currency_from_locale(%Localize.LanguageTag{territory: territory})
      when not is_nil(territory) do
    current_currency_for_territory(territory)
  end

  def current_currency_from_locale(%Localize.LanguageTag{}) do
    nil
  end

  # ── Locale-specific functions (stubs) ────────────────────────

  @doc """
  Returns the currency metadata for the requested currency code
  in the given locale.

  This function requires locale-specific currency data which is
  not yet implemented.

  ### Arguments

  * `currency_code` is an atom or string currency code.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier or language tag.

  ### Returns

  * `{:error, :not_yet_implemented}`.

  """
  @spec currency_for_code(atom() | String.t(), Keyword.t()) ::
          {:ok, t()} | {:error, :not_yet_implemented | Exception.t()}
  def currency_for_code(_currency_code, _options \\ []) do
    {:error, :not_yet_implemented}
  end

  @doc """
  Returns a map of all currencies for a given locale.

  This function requires locale-specific currency data which is
  not yet implemented.

  ### Arguments

  * `locale` is a locale identifier or language tag.

  * `only` is a filter for currency status. Default `:all`.

  * `except` is a filter for currencies to exclude. Default `nil`.

  ### Returns

  * `{:error, :not_yet_implemented}`.

  """
  @spec currencies_for_locale(
          Localize.LanguageTag.t() | atom() | String.t(),
          filter(),
          filter()
        ) ::
          {:ok, map()} | {:error, :not_yet_implemented}
  def currencies_for_locale(_locale, _only \\ :all, _except \\ nil) do
    {:error, :not_yet_implemented}
  end

  @doc """
  Returns a map matching currency strings to currency codes
  for a given locale.

  This function requires locale-specific currency data which is
  not yet implemented.

  ### Arguments

  * `locale` is a locale identifier or language tag.

  * `only` is a filter for currency status. Default `:all`.

  * `except` is a filter for currencies to exclude. Default `nil`.

  ### Returns

  * `{:error, :not_yet_implemented}`.

  """
  @spec currency_strings(
          Localize.LanguageTag.t() | atom() | String.t(),
          filter(),
          filter()
        ) ::
          {:ok, map()} | {:error, :not_yet_implemented}
  def currency_strings(_locale, _only \\ :all, _except \\ nil) do
    {:error, :not_yet_implemented}
  end

  @doc """
  Returns the display name for a currency.

  This function requires locale-specific currency data which is
  not yet implemented.

  ### Arguments

  * `currency` is a currency code or `t:Localize.Currency.t/0` struct.

  * `options` is a keyword list of options.

  ### Returns

  * `{:error, :not_yet_implemented}`.

  """
  @spec display_name(atom() | t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, :not_yet_implemented | Exception.t()}
  def display_name(_currency, _options \\ []) do
    {:error, :not_yet_implemented}
  end

  @doc """
  Returns the appropriate currency display name based on
  plural rules for the locale.

  This function requires locale-specific currency data which is
  not yet implemented.

  ### Arguments

  * `number` is an integer, float, or Decimal.

  * `currency` is a currency code atom.

  * `options` is a keyword list of options.

  ### Returns

  * `{:error, :not_yet_implemented}`.

  """
  @spec pluralize(number(), currency_code(), Keyword.t()) ::
          {:ok, String.t()} | {:error, :not_yet_implemented}
  def pluralize(_number, _currency, _options \\ []) do
    {:error, :not_yet_implemented}
  end

  # ── Currency status predicates ───────────────────────────────

  @doc """
  Returns whether a currency is historic (no longer in use).

  ### Arguments

  * `currency` is a `t:Localize.Currency.t/0` struct.

  ### Returns

  * `true` or `false`.

  """
  @spec historic?(t()) :: boolean()
  def historic?(%__MODULE__{} = currency) do
    is_nil(currency.iso_digits) ||
      (is_integer(currency.to) && currency.to < Date.utc_today().year)
  end

  @doc """
  Returns whether a currency is legal tender.

  ### Arguments

  * `currency` is a `t:Localize.Currency.t/0` struct.

  ### Returns

  * `true` or `false`.

  """
  @spec tender?(t()) :: boolean()
  def tender?(%__MODULE__{} = currency) do
    !!currency.tender
  end

  @doc """
  Returns whether a currency is currently in use.

  ### Arguments

  * `currency` is a `t:Localize.Currency.t/0` struct.

  ### Returns

  * `true` or `false`.

  """
  @spec current?(t()) :: boolean()
  def current?(%__MODULE__{} = currency) do
    !is_nil(currency.iso_digits) && is_nil(currency.to)
  end

  @doc """
  Returns whether a currency name contains annotations.

  Annotated currencies typically have parenthetical descriptions
  and are often financial instruments rather than legal tender.

  ### Arguments

  * `currency` is a `t:Localize.Currency.t/0` struct.

  ### Returns

  * `true` or `false`.

  """
  @spec annotated?(t()) :: boolean()
  def annotated?(%__MODULE__{} = currency) do
    String.contains?(currency.name, "(")
  end

  @doc """
  Returns whether a currency name does not contain annotations.

  ### Arguments

  * `currency` is a `t:Localize.Currency.t/0` struct.

  ### Returns

  * `true` or `false`.

  """
  @spec unannotated?(t()) :: boolean()
  def unannotated?(%__MODULE__{} = currency) do
    !annotated?(currency)
  end

  # ── Private helpers ──────────────────────────────────────────

  defp validate_custom_currency_code(currency_code) when is_binary(currency_code) do
    upcase_code = String.upcase(currency_code)

    if Regex.match?(@valid_custom_currency_code, upcase_code) ||
         Regex.match?(@valid_private_currency_code, upcase_code) do
      {:ok, String.to_atom(upcase_code)}
    else
      {:error, Localize.UnknownCurrencyError.exception(currency: currency_code)}
    end
  end

  defp validate_custom_currency_code(currency_code) when is_atom(currency_code) do
    validate_custom_currency_code(to_string(currency_code))
  end

  defp validate_options(code, options) do
    if options[:name] && options[:digits] do
      validated = [
        code: code,
        alt_code: options[:alt_code] || code,
        name: options[:name],
        symbol: options[:symbol] || to_string(code),
        narrow_symbol: options[:narrow_symbol] || options[:symbol],
        digits: options[:digits],
        rounding: options[:round_nearest] || 0,
        cash_digits: options[:cash_digits] || options[:digits],
        cash_rounding: options[:cash_round_nearest] || options[:round_nearest],
        iso_digits: options[:digits],
        tender: options[:tender] || false,
        count: options[:count] || %{other: options[:name]}
      ]

      {:ok, validated}
    else
      {:error,
       Localize.InvalidValueError.exception(
         value: options,
         expected: "options with :name and :digits keys",
         context: "Localize.Currency.new/2"
       )}
    end
  end
end
