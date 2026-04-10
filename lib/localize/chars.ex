defprotocol Localize.Chars do
  @moduledoc """
  Protocol for locale-aware string formatting.

  `Localize.Chars` provides a single dispatch point for formatting
  any supported value as a localized string. It mirrors the
  `String.Chars` protocol from Elixir core, but every implementation
  is locale-aware and returns the standard Localize result tuple
  `{:ok, formatted}` / `{:error, exception}`.

  ## Examples

      iex> Localize.Chars.to_string(1234.5, locale: :de)
      {:ok, "1.234,5"}

      iex> Localize.Chars.to_string(1234.5, locale: :en)
      {:ok, "1,234.5"}

      iex> Localize.Chars.to_string(~D[2025-07-10], locale: :en)
      {:ok, "Jul 10, 2025"}

      iex> {:ok, unit} = Localize.Unit.new(42, "kilometer")
      iex> Localize.Chars.to_string(unit, format: :short, locale: :en)
      {:ok, "42 km"}

  ## Built-in implementations

  | Type | Delegates to |
  |---|---|
  | `Integer` | `Localize.Number.to_string/2` |
  | `Float` | `Localize.Number.to_string/2` |
  | `Decimal` | `Localize.Number.to_string/2` |
  | `Date` | `Localize.Date.to_string/2` |
  | `Time` | `Localize.Time.to_string/2` |
  | `DateTime` | `Localize.DateTime.to_string/2` |
  | `NaiveDateTime` | `Localize.DateTime.to_string/2` |
  | `Range` | `Localize.Number.to_range_string/2` |
  | `BitString` | identity (returns the string unchanged) |
  | `List` | `Localize.List.to_string/2` |
  | `Localize.Unit` | `Localize.Unit.to_string/2` |
  | `Localize.Duration` | `Localize.Duration.to_string/2` |
  | `Localize.LanguageTag` | `Localize.Locale.LocaleDisplay.display_name/2` |
  | `Localize.Currency` | `Localize.Currency.display_name/2` |

  Unknown types raise `Protocol.UndefinedError` — `Localize.Chars`
  is declared with `@fallback_to_any false` so silent fallback to
  `String.Chars`-style coercion does not happen. Pass values
  through the appropriate Localize formatter explicitly if you
  need a different conversion.

  ## Caveats

  * The `List` implementation delegates to `Localize.List.to_string/2`,
    which formats a list as a localized conjunction (`"a, b, and c"`).
    The list elements are expected to be strings (or values whose
    `String.Chars` form is meaningful). To format a list of
    non-string values you usually want to format each element first
    with `Localize.Chars.to_string/2` and then pass the resulting
    list of strings.

  * The `Localize.LanguageTag` implementation produces the
    **localized display name** ("English (United States)"), not
    the canonical BCP-47 string. The canonical form is still
    available via `Kernel.to_string/1`, which uses the internal
    `String.Chars` protocol.

  ## Adding implementations for your own types

  Implement the protocol for any struct you want to support
  through `Localize.to_string/1` and `Localize.to_string/2`:

      defimpl Localize.Chars, for: MyApp.Money do
        def to_string(money), do: Localize.Chars.to_string(money, [])

        def to_string(%MyApp.Money{amount: amount, currency: currency}, options) do
          options = Keyword.put_new(options, :currency, currency)
          Localize.Number.to_string(amount, options)
        end
      end

  After this, `Localize.to_string(%MyApp.Money{...}, locale: :de)`
  works exactly like the built-in implementations.

  """

  @fallback_to_any false

  @doc """
  Formats `value` as a localized string with default options.

  Equivalent to `to_string(value, [])`.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, exception}` if formatting fails. The exception is a
    struct (e.g. `%Localize.UnknownLocaleError{}`).

  """
  @spec to_string(t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def to_string(value)

  @doc """
  Formats `value` as a localized string with the given options.

  Each implementation accepts the option set of its underlying
  formatter. Every implementation accepts at least `:locale`.

  ### Arguments

  * `value` is any term that has a `Localize.Chars` implementation.

  * `options` is a keyword list of options forwarded to the
    underlying formatter.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, exception}` if formatting fails.

  """
  @spec to_string(t(), Keyword.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def to_string(value, options)
end

# ── Built-in implementations ─────────────────────────────────────

defimpl Localize.Chars, for: Integer do
  def to_string(value), do: Localize.Number.to_string(value, [])
  def to_string(value, options), do: Localize.Number.to_string(value, options)
end

defimpl Localize.Chars, for: Float do
  def to_string(value), do: Localize.Number.to_string(value, [])
  def to_string(value, options), do: Localize.Number.to_string(value, options)
end

defimpl Localize.Chars, for: Decimal do
  def to_string(value), do: Localize.Number.to_string(value, [])
  def to_string(value, options), do: Localize.Number.to_string(value, options)
end

defimpl Localize.Chars, for: Date do
  def to_string(value), do: Localize.Date.to_string(value, [])
  def to_string(value, options), do: Localize.Date.to_string(value, options)
end

defimpl Localize.Chars, for: Time do
  def to_string(value), do: Localize.Time.to_string(value, [])
  def to_string(value, options), do: Localize.Time.to_string(value, options)
end

defimpl Localize.Chars, for: DateTime do
  def to_string(value), do: Localize.DateTime.to_string(value, [])
  def to_string(value, options), do: Localize.DateTime.to_string(value, options)
end

defimpl Localize.Chars, for: NaiveDateTime do
  def to_string(value), do: Localize.DateTime.to_string(value, [])
  def to_string(value, options), do: Localize.DateTime.to_string(value, options)
end

defimpl Localize.Chars, for: Range do
  def to_string(value), do: Localize.Number.to_range_string(value, [])
  def to_string(value, options), do: Localize.Number.to_range_string(value, options)
end

defimpl Localize.Chars, for: BitString do
  def to_string(value) when is_binary(value), do: {:ok, value}
  def to_string(value, _options) when is_binary(value), do: {:ok, value}
end

defimpl Localize.Chars, for: List do
  def to_string(value), do: Localize.List.to_string(value, [])
  def to_string(value, options), do: Localize.List.to_string(value, options)
end

defimpl Localize.Chars, for: Localize.Unit do
  def to_string(value), do: Localize.Unit.to_string(value, [])
  def to_string(value, options), do: Localize.Unit.to_string(value, options)
end

defimpl Localize.Chars, for: Localize.Duration do
  def to_string(value), do: Localize.Duration.to_string(value, [])
  def to_string(value, options), do: Localize.Duration.to_string(value, options)
end

defimpl Localize.Chars, for: Localize.LanguageTag do
  def to_string(value), do: Localize.Locale.LocaleDisplay.display_name(value, [])

  def to_string(value, options),
    do: Localize.Locale.LocaleDisplay.display_name(value, options)
end

defimpl Localize.Chars, for: Localize.Currency do
  def to_string(value), do: Localize.Currency.display_name(value, [])
  def to_string(value, options), do: Localize.Currency.display_name(value, options)
end
