defmodule Localize.Currency do
  @moduledoc """
  Defines a currency structure and functions to manage currency
  codes, validate currencies, and retrieve currency metadata.

  Currency data is derived from the Unicode CLDR repository and
  includes all ISO 4217 currency codes and territory-to-currency
  mappings.

  Locale-specific currency data (display names, pluralized names,
  symbols) is loaded on demand from the locale data provider.

  """

  alias Localize.SupplementalData
  alias Localize.Utils.Helpers

  @type currency_code :: atom()

  @type currency_status :: :all | :current | :historic | :tender | :unannotated

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
          iso_digits: non_neg_integer() | nil,
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
    # Gate atomisation on membership in the validity set so unknown
    # string codes can't grow the atom table on each call. The error
    # always carries the caller's binary, never the atom — whether
    # the atom happens to exist depends on unrelated prior code.
    case currency_code |> String.upcase() |> Helpers.existing_atom() do
      nil ->
        {:error, Localize.UnknownCurrencyError.exception(currency: currency_code)}

      atom ->
        case validate_currency(atom) do
          {:ok, code} ->
            {:ok, code}

          {:error, _} ->
            {:error, Localize.UnknownCurrencyError.exception(currency: currency_code)}
        end
    end
  end

  def validate_currency(currency_code) when is_atom(currency_code) do
    if currency_code in known_currency_codes() do
      {:ok, currency_code}
    else
      {:error, Localize.UnknownCurrencyError.exception(currency: currency_code)}
    end
  end

  # ── Known currencies ─────────────────────────────────────────

  @doc """
  Returns a list of all known currency codes.

  ### Returns

  * A list of atom currency codes.

  ### Examples

      iex> codes = Localize.Currency.known_currency_codes()
      iex> :USD in codes
      true

  """
  @spec known_currency_codes() :: [currency_code(), ...]
  def known_currency_codes do
    SupplementalData.currency_codes()
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
  @dialyzer {:nowarn_function, territory_currencies: 0}
  @spec territory_currencies() :: %{required(atom()) => %{required(atom()) => map()}}
  def territory_currencies do
    SupplementalData.territory_currencies()
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
    case territory |> String.upcase() |> Helpers.existing_atom() do
      nil ->
        {:error, Localize.UnknownTerritoryError.exception(territory: territory)}

      atom ->
        territory_currencies(atom)
    end
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
    case territory |> String.upcase() |> Helpers.existing_atom() do
      nil -> nil
      atom -> current_currency_for_territory(atom)
    end
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
  Returns the effective currency for a given locale.

  If the language tag has a `cu` Unicode extension key set,
  that currency is returned. Otherwise, the current currency
  for the tag's territory is returned.

  ### Arguments

  * `locale` is a locale identifier string, atom, or a
    `t:Localize.LanguageTag.t/0` struct.

  ### Returns

  * `{:ok, currency_code}` where `currency_code` is an atom.

  * `{:error, exception}` if the locale is not valid.

  ### Examples

      iex> {:ok, tag} = Localize.LanguageTag.parse("en-US")
      iex> Localize.Currency.currency_from_locale(tag)
      {:ok, :USD}

      iex> Localize.Currency.currency_from_locale("en-AU")
      {:ok, :AUD}

  """
  @spec currency_from_locale(Localize.LanguageTag.t() | String.t() | atom()) ::
          {:ok, currency_code()} | {:error, Exception.t()}
  def currency_from_locale(locale) when is_binary(locale) or is_atom(locale) do
    with {:ok, language_tag} <- Localize.validate_locale(locale) do
      currency_from_locale(language_tag)
    end
  end

  def currency_from_locale(%Localize.LanguageTag{locale: %{cu: nil}} = locale) do
    current_currency_from_locale(locale)
  end

  def currency_from_locale(%Localize.LanguageTag{locale: %{cu: currency}}) do
    {:ok, currency}
  end

  def currency_from_locale(%Localize.LanguageTag{} = locale) do
    current_currency_from_locale(locale)
  end

  @doc """
  Returns the effective currency format for a given locale.

  If the language tag has a `cf` Unicode extension key set to
  `:account`, returns `:accounting`. Otherwise returns `:currency`.

  ### Arguments

  * `locale` is a locale identifier string, atom, or a
    `t:Localize.LanguageTag.t/0` struct.

  ### Returns

  * `{:ok, format}` where `format` is `:currency` or `:accounting`.

  * `{:error, exception}` if the locale is not valid.

  ### Examples

      iex> {:ok, tag} = Localize.LanguageTag.parse("en-US")
      iex> Localize.Currency.currency_format_from_locale(tag)
      {:ok, :currency}

      iex> Localize.Currency.currency_format_from_locale("en-US")
      {:ok, :currency}

  """
  @spec currency_format_from_locale(Localize.LanguageTag.t() | String.t() | atom()) ::
          {:ok, :currency | :accounting} | {:error, Exception.t()}
  def currency_format_from_locale(locale) when is_binary(locale) or is_atom(locale) do
    with {:ok, language_tag} <- Localize.validate_locale(locale) do
      currency_format_from_locale(language_tag)
    end
  end

  def currency_format_from_locale(%Localize.LanguageTag{locale: %{cf: :account}}) do
    {:ok, :accounting}
  end

  def currency_format_from_locale(%Localize.LanguageTag{}) do
    {:ok, :currency}
  end

  @doc """
  Returns the current currency for a locale's territory.

  This function does not consider the `U` extension parameter `cu`.
  Use `currency_from_locale/1` to get the effective currency
  including overrides.

  ### Arguments

  * `locale` is a locale identifier string, atom, or a
    `t:Localize.LanguageTag.t/0` struct.

  ### Returns

  * `{:ok, currency_code}` where `currency_code` is an atom.

  * `{:ok, nil}` if the locale has no territory or the territory
    has no current currency.

  * `{:error, exception}` if the locale is not valid.

  ### Examples

      iex> {:ok, tag} = Localize.LanguageTag.parse("en-AU")
      iex> Localize.Currency.current_currency_from_locale(tag)
      {:ok, :AUD}

      iex> Localize.Currency.current_currency_from_locale("en-US")
      {:ok, :USD}

  """
  @spec current_currency_from_locale(Localize.LanguageTag.t() | String.t() | atom()) ::
          {:ok, currency_code() | nil} | {:error, Exception.t()}
  def current_currency_from_locale(locale) when is_binary(locale) or is_atom(locale) do
    with {:ok, language_tag} <- Localize.validate_locale(locale) do
      current_currency_from_locale(language_tag)
    end
  end

  def current_currency_from_locale(%Localize.LanguageTag{} = locale) do
    with {:ok, territory} <- Localize.Territory.territory_from_locale(locale) do
      {:ok, current_currency_for_territory(territory)}
    end
  end

  @doc """
  Returns the full currency history for a locale's territory.

  Resolves the territory from the locale using
  `Localize.Territory.territory_from_locale/1` (which considers the `rg` extension,
  the explicit territory, and likely subtags), then returns the
  currency history for that territory.

  ### Arguments

  * `locale` is a locale identifier string, atom, or a
    `t:Localize.LanguageTag.t/0` struct.

  ### Returns

  * `{:ok, currency_map}` where `currency_map` is a map of
    `%{currency_code => %{from: date, to: date, ...}}` entries.

  * `{:error, exception}` if the locale or territory cannot
    be resolved.

  ### Examples

      iex> {:ok, history} = Localize.Currency.currency_history_for_locale("en-US")
      iex> Map.has_key?(history, :USD)
      true

      iex> {:ok, history} = Localize.Currency.currency_history_for_locale("de")
      iex> Map.has_key?(history, :EUR)
      true

      iex> {:ok, history} = Localize.Currency.currency_history_for_locale("ja")
      iex> Map.has_key?(history, :JPY)
      true

  """
  @spec currency_history_for_locale(Localize.LanguageTag.t() | String.t() | atom()) ::
          {:ok, map()} | {:error, Exception.t()}
  def currency_history_for_locale(locale) when is_binary(locale) or is_atom(locale) do
    with {:ok, language_tag} <- Localize.validate_locale(locale) do
      currency_history_for_locale(language_tag)
    end
  end

  def currency_history_for_locale(%Localize.LanguageTag{} = locale) do
    with {:ok, territory} <- Localize.Territory.territory_from_locale(locale) do
      territory_currencies(territory)
    end
  end

  # ── Locale-specific currency functions ────────────────────────

  @doc """
  Returns the currency metadata for the requested currency code
  in the given locale.

  Looks up localized currency data (display name, symbol, plural
  forms) for a specific currency code.

  ### Arguments

  * `currency_code` is an atom or string currency code.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier atom or a
    `t:Localize.LanguageTag.t/0`. The default is the current
    process locale (see `Localize.get_locale/0`).

  * `:fallback` is a boolean. When `true`, if the currency has
    no entry in the requested locale's currency map, the CLDR
    parent locale chain is walked, followed by the application
    default locale (`Localize.default_locale/0`), looking for
    localized data. The default is `false`.

  ### Returns

  * `{:ok, Localize.Currency.t()}` with localized currency metadata.

  * `{:error, %Localize.UnknownCurrencyError{}}` if the currency
    code is not a known ISO 4217 or registered custom currency.

  * `{:error, %Localize.CurrencyNotLocalizedError{}}` if the
    currency code is valid but has no entry in the requested
    locale (and, when `:fallback` is `true`, no entry in any
    fallback locale either).

  * `{:error, exception}` if the locale data cannot be loaded.

  ### Examples

      iex> {:ok, currency} = Localize.Currency.currency_for_code(:USD, locale: :en)
      iex> currency.name
      "US Dollar"

      iex> Localize.Currency.currency_for_code(:VED, locale: :es)
      {:error, %Localize.CurrencyNotLocalizedError{currency: :VED, locale: :es}}

      iex> {:ok, currency} = Localize.Currency.currency_for_code(:VED, locale: :es, fallback: true)
      iex> currency.code
      :VED

  """
  @spec currency_for_code(atom() | String.t(), Keyword.t()) ::
          {:ok, t()} | {:error, Exception.t()}
  def currency_for_code(currency_code, options \\ []) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    fallback? = Keyword.get(options, :fallback, false)

    with {:ok, code} <- validate_currency(currency_code) do
      resolve_currency_for_code(code, locale, fallback?)
    end
  end

  defp resolve_currency_for_code(code, locale, fallback?) do
    with {:ok, locale_id} <- Localize.Locale.cldr_locale_id_from(locale) do
      case Localize.Locale.get(locale_id, [:currencies, code],
             fallback: fallback?,
             fallback_to_default: fallback?
           ) do
        {:ok, currency} ->
          {:ok, currency}

        {:error, %Localize.ItemNotFoundError{}} ->
          {:error, currency_not_localized_error(code, locale_id)}

        {:error, _} = error ->
          error
      end
    end
  end

  defp currency_not_localized_error(code, locale_id) do
    Localize.CurrencyNotLocalizedError.exception(
      currency: code,
      locale: locale_id
    )
  end

  # Normalizes the second argument of the filter-taking public
  # functions. Only a keyword list is accepted; the pre-1.0
  # positional :only filter (an atom, or a plain list of statuses
  # and currency codes — which a bare is_list/1 guard cannot
  # discriminate from a keyword list) raises so it cannot be
  # silently misread as empty options.
  defp filter_options(_fun, [{key, _} | _] = options) when is_atom(key) do
    {Keyword.get(options, :only, :all), Keyword.get(options, :except)}
  end

  defp filter_options(_fun, []) do
    {:all, nil}
  end

  defp filter_options(fun, other) do
    raise ArgumentError,
          "Localize.Currency.#{fun} takes a keyword list of options. " <>
            "The positional :only/:except filter arguments were removed in Localize 1.0 — " <>
            "use the :only and :except options instead. Got: #{inspect(other)}"
  end

  @doc """
  Returns a map of all currencies for a given locale.

  Each key is a currency code atom and each value is a
  `t:Localize.Currency.t/0` struct with localized display names,
  symbols, and plural forms. The result can be filtered by
  currency status.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:only` is a filter of currencies to include: a currency
    status (`:all`, `:current`, `:historic`, `:tender` or
    `:unannotated`), a currency code, or a list combining them.
    The default is `:all`.

  * `:except` is a filter of currencies to exclude, in the same
    form as `:only`. The default is `nil` (exclude none).

  ### Returns

  * `{:ok, currencies_map}` where `currencies_map` is a map of
    `%{currency_code => Localize.Currency.t()}`.

  * `{:error, exception}` if the locale data cannot be loaded.

  ### Examples

      iex> {:ok, currencies} = Localize.Currency.currencies_for_locale(:en)
      iex> Map.has_key?(currencies, :USD)
      true

      iex> {:ok, currencies} = Localize.Currency.currencies_for_locale(:en, except: :historic)
      iex> {map_size(currencies) > 0, Map.has_key?(currencies, :SDP)}
      {true, false}

  """
  @spec currencies_for_locale(
          Localize.LanguageTag.t() | atom() | String.t(),
          Keyword.t() | filter()
        ) ::
          {:ok, map()} | {:error, Exception.t()}
  def currencies_for_locale(locale, options \\ []) do
    {only, except} = filter_options("currencies_for_locale/2", options)
    do_currencies_for_locale(locale, only, except)
  end

  defp do_currencies_for_locale(locale, only, except) do
    with {:ok, locale_id} <- cldr_locale_id_from(locale),
         {:ok, currencies} <- Localize.Locale.get(locale_id, [:currencies]) do
      {:ok, currency_filter(currencies, only, except)}
    end
  end

  @doc """
  Returns a map matching currency strings to currency codes
  for a given locale.

  A currency string is a localized name or symbol representing
  a currency in a locale-specific manner. The map can be used
  to parse user input into currency codes.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:only` is a filter of currencies to include: a currency
    status (`:all`, `:current`, `:historic`, `:tender` or
    `:unannotated`), a currency code, or a list combining them.
    The default is `:all`.

  * `:except` is a filter of currencies to exclude, in the same
    form as `:only`. The default is `nil` (exclude none).

  ### Returns

  * `{:ok, string_map}` where `string_map` is a map of
    `%{downcased_string => currency_code}`.

  * `{:error, exception}` if the locale data cannot be loaded.

  ### Examples

      iex> {:ok, strings} = Localize.Currency.currency_strings(:en)
      iex> Map.get(strings, "us dollar")
      :USD

      iex> {:ok, strings} = Localize.Currency.currency_strings(:en)
      iex> Map.get(strings, "aud")
      :AUD

  """
  @spec currency_strings(
          Localize.LanguageTag.t() | atom() | String.t(),
          Keyword.t() | filter()
        ) ::
          {:ok, map()} | {:error, Exception.t()}
  def currency_strings(locale, options \\ []) do
    {only, except} = filter_options("currency_strings/2", options)
    do_currency_strings(locale, only, except)
  end

  defp do_currency_strings(locale, only, except) do
    with {:ok, currencies} <- do_currencies_for_locale(locale, only, except) do
      {:ok, build_currency_strings(currencies)}
    end
  end

  @doc """
  Returns the list of strings that map to a given currency
  code in a locale.

  This is the inverse of `currency_strings/2` filtered to a
  single currency. It returns all localized representations
  (name, symbol, plural forms) that identify the currency.

  ### Arguments

  * `currency` is a currency code atom or string.

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * `{:ok, strings}` where `strings` is a list of downcased
    strings that represent the currency in the locale.

  * `{:error, exception}` if the currency is unknown or the
    locale data cannot be loaded.

  ### Examples

      iex> {:ok, strings} = Localize.Currency.strings_for_currency(:USD, :en)
      iex> Enum.sort(strings)
      ["$", "us dollar", "us dollars", "usd"]

  """
  @spec strings_for_currency(
          currency_code() | String.t(),
          Localize.LanguageTag.t() | atom() | String.t()
        ) ::
          {:ok, [String.t()]} | {:error, Exception.t()}
  def strings_for_currency(currency, locale) do
    with {:ok, currency_code} <- validate_currency(currency),
         {:ok, strings} <- currency_strings(locale) do
      result =
        strings
        |> Enum.filter(fn {_string, code} -> code == currency_code end)
        |> Enum.map(fn {string, _code} -> string end)

      {:ok, result}
    end
  end

  @doc """
  Returns the display name for a currency.

  When given a `t:Localize.Currency.t/0` struct, returns its
  `:name` field directly. When given a currency code, looks up
  the localized name from the locale data.

  ### Arguments

  * `currency` is a currency code atom, string, or a
    `t:Localize.Currency.t/0` struct.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier atom or a
    `t:Localize.LanguageTag.t/0`. The default is `:en`.

  ### Returns

  * `{:ok, display_name}` where `display_name` is a string.

  * `{:error, exception}` if the currency has no display name
    or is unknown.

  ### Examples

      iex> Localize.Currency.display_name(:USD, locale: :en)
      {:ok, "US Dollar"}

      iex> Localize.Currency.display_name(:AUD, locale: :en)
      {:ok, "Australian Dollar"}

  """
  @spec display_name(atom() | String.t() | t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def display_name(currency, options \\ [])

  def display_name(%__MODULE__{name: nil, code: code}, _options) do
    {:error, Localize.CurrencyNoDisplayNameError.exception(currency: code)}
  end

  def display_name(%__MODULE__{name: name}, _options) do
    {:ok, name}
  end

  def display_name(currency_code, options) do
    with {:ok, currency_data} <- currency_for_code(currency_code, options) do
      display_name(currency_data, options)
    end
  end

  @doc """
  Returns the currency symbol of the requested kind.

  The same resolution rules that `Localize.Number.to_string/2`'s
  `:currency_symbol` option applies, surfaced as a standalone
  function so callers building locale-aware UIs can resolve a
  symbol without going through the full number formatter.

  ### Arguments

  * `currency` is a `t/0` (already locale-resolved) or a
    currency code (atom or string).

  * `kind` is one of `:standard` (default), `:symbol`,
    `:narrow`, `:iso`, `:none`, or a literal binary which is
    returned as-is. `:standard` and `:symbol` both pick the
    locale's standard symbol; `:narrow` prefers the
    narrow-form symbol; `:iso` returns the ISO 4217 code;
    `:none` returns an empty string.

  ### Returns

  * `{:ok, binary}` on success.

  * `{:error, exception}` when the currency code can't be
    resolved.

  ### Examples

      iex> {:ok, c} = Localize.Currency.currency_for_code(:USD)
      iex> Localize.Currency.symbol(c, :standard)
      {:ok, "$"}

      iex> Localize.Currency.symbol(:USD, :iso)
      {:ok, "USD"}

      iex> Localize.Currency.symbol(:USD, :none)
      {:ok, ""}

  """
  @spec symbol(t() | atom() | String.t(), atom() | String.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def symbol(currency, kind \\ :standard)

  def symbol(%__MODULE__{} = currency, kind), do: {:ok, do_symbol(currency, kind)}

  def symbol(currency_code, kind) do
    with {:ok, currency} <- currency_for_code(currency_code) do
      symbol(currency, kind)
    end
  end

  defp do_symbol(%__MODULE__{} = c, :narrow), do: c.narrow_symbol || c.symbol || iso_code(c)
  defp do_symbol(%__MODULE__{} = c, :iso), do: iso_code(c)
  defp do_symbol(%__MODULE__{} = c, :symbol), do: c.symbol || iso_code(c)
  defp do_symbol(%__MODULE__{} = c, :standard), do: c.symbol || iso_code(c)
  defp do_symbol(%__MODULE__{}, :none), do: ""
  defp do_symbol(%__MODULE__{} = c, nil), do: c.symbol || iso_code(c)
  defp do_symbol(%__MODULE__{}, other) when is_binary(other), do: other
  defp do_symbol(%__MODULE__{} = c, _other), do: c.symbol || iso_code(c)

  defp iso_code(%__MODULE__{code: code}), do: Atom.to_string(code)

  @doc """
  Returns the appropriate currency display name based on
  plural rules for the locale.

  Uses the locale's cardinal plural rules to determine which
  plural form of the currency name to use for the given number.

  ### Arguments

  * `number` is an integer, float, or Decimal.

  * `currency` is a currency code atom.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier atom or a
    `t:Localize.LanguageTag.t/0`. The default is `:en`.

  ### Returns

  * `{:ok, pluralized_name}` where `pluralized_name` is the
    appropriate plural form string.

  * `{:error, exception}` if the currency is unknown or the
    locale data cannot be loaded.

  ### Examples

      iex> Localize.Currency.pluralize(1, :USD, locale: :en)
      {:ok, "US dollar"}

      iex> Localize.Currency.pluralize(3, :USD, locale: :en)
      {:ok, "US dollars"}

  """
  @spec pluralize(number(), currency_code(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def pluralize(number, currency, options \\ []) do
    locale = Keyword.get(options, :locale, Localize.get_locale())

    with {:ok, currency_code} <- validate_currency(currency),
         {:ok, currency_data} <- currency_for_code(currency_code, locale: locale) do
      counts =
        (currency_data.count || %{})
        |> Map.put_new(:other, currency_data.name)

      plural_category =
        Localize.Number.PluralRule.Cardinal.plural_rule(number, locale)

      {:ok, Map.get(counts, plural_category, counts[:other])}
    end
  end

  # ── Bang versions ──────────────────────────────────────────

  @doc """
  Same as `currency_for_code/2` but raises on error.

  ### Arguments

  * `currency_code` is an atom or string currency code.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier atom or a
    `t:Localize.LanguageTag.t/0`. The default is `:en`.

  ### Returns

  * A `t:Localize.Currency.t/0` struct.

  ### Raises

  * Raises an exception if the currency code is unknown or the
    locale data cannot be loaded.

  ### Examples

      iex> currency = Localize.Currency.currency_for_code!(:USD, locale: :en)
      iex> currency.name
      "US Dollar"

      iex> currency = Localize.Currency.currency_for_code!(:USD, locale: :en)
      iex> currency.digits
      2

  """
  @spec currency_for_code!(atom() | String.t(), Keyword.t()) :: t()
  def currency_for_code!(currency_code, options \\ []) do
    case currency_for_code(currency_code, options) do
      {:ok, currency} -> currency
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Same as `currencies_for_locale/2` but raises on error.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:only` is a filter of currencies to include: a currency
    status (`:all`, `:current`, `:historic`, `:tender` or
    `:unannotated`), a currency code, or a list combining them.
    The default is `:all`.

  * `:except` is a filter of currencies to exclude, in the same
    form as `:only`. The default is `nil` (exclude none).

  ### Returns

  * A map of `%{currency_code => Localize.Currency.t()}`.

  ### Raises

  * Raises an exception if the locale data cannot be loaded.

  ### Examples

      iex> currencies = Localize.Currency.currencies_for_locale!(:en)
      iex> Map.has_key?(currencies, :USD)
      true

  """
  @spec currencies_for_locale!(
          Localize.LanguageTag.t() | atom() | String.t(),
          Keyword.t() | filter()
        ) :: map()
  def currencies_for_locale!(locale, options \\ []) do
    {only, except} = filter_options("currencies_for_locale!/2", options)

    case do_currencies_for_locale(locale, only, except) do
      {:ok, currencies} -> currencies
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Same as `currency_strings/2` but raises on error.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:only` is a filter of currencies to include: a currency
    status (`:all`, `:current`, `:historic`, `:tender` or
    `:unannotated`), a currency code, or a list combining them.
    The default is `:all`.

  * `:except` is a filter of currencies to exclude, in the same
    form as `:only`. The default is `nil` (exclude none).

  ### Returns

  * A map of `%{downcased_string => currency_code}`.

  ### Raises

  * Raises an exception if the locale data cannot be loaded.

  ### Examples

      iex> strings = Localize.Currency.currency_strings!(:en)
      iex> Map.get(strings, "us dollar")
      :USD

  """
  @spec currency_strings!(
          Localize.LanguageTag.t() | atom() | String.t(),
          Keyword.t() | filter()
        ) :: map()
  def currency_strings!(locale, options \\ []) do
    {only, except} = filter_options("currency_strings!/2", options)

    case do_currency_strings(locale, only, except) do
      {:ok, strings} -> strings
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Same as `display_name/2` but raises on error.

  ### Arguments

  * `currency` is a currency code atom, string, or a
    `t:Localize.Currency.t/0` struct.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier atom or a
    `t:Localize.LanguageTag.t/0`. The default is `:en`.

  ### Returns

  * A display name string.

  ### Raises

  * Raises an exception if the currency has no display name
    or is unknown.

  ### Examples

      iex> Localize.Currency.display_name!(:USD, locale: :en)
      "US Dollar"

      iex> Localize.Currency.display_name!(:AUD, locale: :en)
      "Australian Dollar"

  """
  @spec display_name!(atom() | String.t() | t(), Keyword.t()) :: String.t()
  def display_name!(currency, options \\ []) do
    case display_name(currency, options) do
      {:ok, name} -> name
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Same as `strings_for_currency/2` but raises on error.

  ### Arguments

  * `currency` is a currency code atom or string.

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * A list of downcased strings that represent the currency
    in the locale.

  ### Raises

  * Raises an exception if the currency is unknown or the
    locale data cannot be loaded.

  ### Examples

      iex> strings = Localize.Currency.strings_for_currency!(:AUD, :en)
      iex> "australian dollar" in strings
      true

  """
  @spec strings_for_currency!(
          currency_code() | String.t(),
          Localize.LanguageTag.t() | atom() | String.t()
        ) ::
          [String.t()]
  def strings_for_currency!(currency, locale) do
    case strings_for_currency(currency, locale) do
      {:ok, strings} -> strings
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Same as `territory_currencies/1` but raises on error.

  ### Arguments

  * `territory` is a territory code atom or string (e.g., `:US` or `"US"`).

  ### Returns

  * A map of currency codes and date ranges.

  ### Raises

  * Raises an exception if no currencies are found for the territory.

  ### Examples

      iex> currencies = Localize.Currency.territory_currencies!(:US)
      iex> Map.has_key?(currencies, :USD)
      true

  """
  @spec territory_currencies!(territory()) :: map()
  def territory_currencies!(territory) do
    case territory_currencies(territory) do
      {:ok, currencies} -> currencies
      {:error, exception} -> raise exception
    end
  end

  # ── Currency filtering ─────────────────────────────────────

  @doc """
  Filters a map of currencies by status predicates.

  ### Arguments

  * `currencies` is a map of `%{currency_code => Localize.Currency.t()}`.

  * `only` is a filter or list of filters to include. The default
    is `:all`.

  * `except` is a filter or list of filters to exclude. The default
    is `nil`.

  ### Returns

  * A filtered map of currencies.

  ### Examples

      iex> {:ok, currencies} = Localize.Currency.currencies_for_locale(:en)
      iex> historic = Localize.Currency.currency_filter(currencies, :historic)
      iex> Map.has_key?(historic, :SDP)
      true

      iex> {:ok, currencies} = Localize.Currency.currencies_for_locale(:en)
      iex> current = Localize.Currency.currency_filter(currencies, :all, :historic)
      iex> {Map.has_key?(current, :USD), Map.has_key?(current, :SDP)}
      {true, false}

  """
  @spec currency_filter(map(), filter(), filter()) :: map()
  def currency_filter(currencies, only \\ :all, except \\ nil)

  def currency_filter(currencies, :all, nil) do
    currencies
  end

  def currency_filter(currencies, only, except) when is_map(currencies) do
    included = expand_filter(currencies, :only, List.wrap(only))
    excluded = expand_filter(currencies, :except, List.wrap(except))

    included
    |> Kernel.--(excluded)
    |> Map.new()
  end

  defp expand_filter(currencies, :only, [:all | _]) do
    Enum.to_list(currencies)
  end

  defp expand_filter(_currencies, :except, [nil]) do
    []
  end

  defp expand_filter(currencies, _, filter_list) do
    currencies_list = Enum.to_list(currencies)

    filter_list
    |> Enum.flat_map(&expand_one_filter(&1, currencies_list))
    |> Enum.uniq()
  end

  defp expand_one_filter(:all, currencies_list), do: currencies_list

  defp expand_one_filter(:historic, currencies_list),
    do: Enum.filter(currencies_list, fn {_, c} -> historic?(c) end)

  defp expand_one_filter(:tender, currencies_list),
    do: Enum.filter(currencies_list, fn {_, c} -> tender?(c) end)

  defp expand_one_filter(:current, currencies_list),
    do: Enum.filter(currencies_list, fn {_, c} -> current?(c) end)

  defp expand_one_filter(:annotated, currencies_list),
    do: Enum.filter(currencies_list, fn {_, c} -> annotated?(c) end)

  defp expand_one_filter(:unannotated, currencies_list),
    do: Enum.filter(currencies_list, fn {_, c} -> unannotated?(c) end)

  defp expand_one_filter(code, currencies_list) when is_atom(code),
    do: Enum.filter(currencies_list, fn {k, _} -> k == code end)

  defp expand_one_filter(code, currencies_list) when is_binary(code) do
    case Helpers.existing_atom(code) do
      nil -> []
      atom_code -> Enum.filter(currencies_list, fn {k, _} -> k == atom_code end)
    end
  end

  # ── Currency status predicates ───────────────────────────────

  @doc """
  Returns whether a currency is historic (no longer in use).

  ### Arguments

  * `currency` is a `t:Localize.Currency.t/0` struct.

  ### Returns

  * `true` or `false`.

  ### Examples

      iex> {:ok, currencies} = Localize.Currency.currencies_for_locale(:en)
      iex> Localize.Currency.historic?(currencies[:SDP])
      true

      iex> {:ok, currencies} = Localize.Currency.currencies_for_locale(:en)
      iex> Localize.Currency.historic?(currencies[:USD])
      false

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

  ### Examples

      iex> {:ok, currencies} = Localize.Currency.currencies_for_locale(:en)
      iex> Localize.Currency.tender?(currencies[:USD])
      true

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

  ### Examples

      iex> {:ok, currencies} = Localize.Currency.currencies_for_locale(:en)
      iex> Localize.Currency.current?(currencies[:USD])
      true

      iex> {:ok, currencies} = Localize.Currency.currencies_for_locale(:en)
      iex> Localize.Currency.current?(currencies[:SDP])
      false

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

  ### Examples

      iex> {:ok, currencies} = Localize.Currency.currencies_for_locale(:en)
      iex> Localize.Currency.annotated?(currencies[:USN])
      true

      iex> {:ok, currencies} = Localize.Currency.currencies_for_locale(:en)
      iex> Localize.Currency.annotated?(currencies[:USD])
      false

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

  ### Examples

      iex> {:ok, currencies} = Localize.Currency.currencies_for_locale(:en)
      iex> Localize.Currency.unannotated?(currencies[:USD])
      true

      iex> {:ok, currencies} = Localize.Currency.currencies_for_locale(:en)
      iex> Localize.Currency.unannotated?(currencies[:USN])
      false

  """
  @spec unannotated?(t()) :: boolean()
  def unannotated?(%__MODULE__{} = currency) do
    !annotated?(currency)
  end

  # ── Private helpers ──────────────────────────────────────────

  @rtl_mark "\u200F"

  defp cldr_locale_id_from(locale), do: Localize.Locale.cldr_locale_id_from(locale)

  defp build_currency_strings(currencies) do
    currency_string_pairs =
      Enum.flat_map(currencies, fn {code, currency} ->
        strings =
          [currency.name, currency.symbol, to_string(code)]
          |> Kernel.++(if currency.count, do: Map.values(currency.count), else: [])
          |> Enum.reject(&is_nil/1)
          |> Enum.map(&String.downcase/1)
          |> Enum.map(&String.trim_trailing(&1, @rtl_mark))
          |> Enum.map(&String.trim_trailing(&1, "."))
          |> Enum.uniq()

        Enum.map(strings, fn string -> {string, code} end)
      end)

    string_map =
      currency_string_pairs
      |> resolve_duplicate_strings(currencies)
      |> Map.new()

    add_unique_narrow_symbols(string_map, currencies)
  end

  defp resolve_duplicate_strings(pairs, currencies) do
    pairs
    |> Enum.sort_by(fn {string, _code} -> string end)
    |> do_resolve_duplicates(currencies)
  end

  defp do_resolve_duplicates([], _currencies), do: []
  defp do_resolve_duplicates([pair], _currencies), do: [pair]

  defp do_resolve_duplicates(
         [{string, code1} = pair1, {string, code2} = pair2 | rest],
         currencies
       ) do
    case prefer_currency(
           pair1,
           Map.get(currencies, code1),
           pair2,
           Map.get(currencies, code2)
         ) do
      {:keep, kept} -> do_resolve_duplicates([kept | rest], currencies)
      :drop_both -> do_resolve_duplicates(rest, currencies)
    end
  end

  defp do_resolve_duplicates([pair | rest], currencies) do
    [pair | do_resolve_duplicates(rest, currencies)]
  end

  # Pick the surviving (string -> code) pair when two share the same
  # string. A current currency wins over a historic one; otherwise both
  # are dropped so the string remains ambiguous and is not auto-resolved.
  defp prefer_currency(pair1, %{} = c1, pair2, %{} = c2) do
    cond do
      historic?(c1) and current?(c2) -> {:keep, pair2}
      current?(c1) and historic?(c2) -> {:keep, pair1}
      true -> :drop_both
    end
  end

  defp prefer_currency(_pair1, _c1, _pair2, _c2), do: :drop_both

  defp add_unique_narrow_symbols(string_map, currencies) do
    Enum.reduce(currencies, string_map, fn {code, currency}, acc ->
      cond do
        is_nil(currency.narrow_symbol) ->
          acc

        Map.has_key?(acc, String.downcase(currency.narrow_symbol)) ->
          acc

        true ->
          Map.put(acc, String.downcase(currency.narrow_symbol), code)
      end
    end)
  end
end
