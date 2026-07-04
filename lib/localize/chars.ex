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

  Types without a Localize-specific implementation fall through to
  `Kernel.to_string/1`, which dispatches via `String.Chars`. This
  mirrors the relationship between `Localize.Chars` and
  `String.Chars`: where Localize knows how to format the type
  in a locale-aware way it does so; otherwise it returns
  `{:ok, Kernel.to_string(value)}`. Types with **no** `String.Chars`
  implementation either (tuples, maps without an explicit impl,
  PIDs, references, anonymous functions) raise the same
  `Protocol.UndefinedError` they would from `Kernel.to_string/1`
  — `Localize.Chars` does not invent a representation for them.

  ## Caveats

  * The `List` implementation formats the list as a locale-aware
    conjunction (`"a, b, and c"`) by delegating to
    `Localize.List.to_string/2`, which itself recursively formats
    each element via `Localize.to_string/2` so dates, numbers,
    units, etc. inside a list pick up the outer locale and other
    options (e.g. `currency: :USD`). **Charlists** are special-cased:
    a printable list of integer codepoints (`~c"hello"`) is
    converted via `Kernel.to_string/1` rather than being joined
    digit-by-digit, mirroring how `String.Chars`'s `List` impl
    handles them.

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

  @fallback_to_any true

  @doc """
  Formats `value` as a localized string with default options.

  Equivalent to `to_string(value, [])`.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, exception}` if formatting fails. The exception is a
    struct (e.g. `%Localize.UnknownLocaleError{}`).

  ### Examples

      iex> Localize.Chars.to_string("hello")
      {:ok, "hello"}

      iex> Localize.Chars.to_string(:hello)
      {:ok, "hello"}

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

  ### Options

  * The options are forwarded unchanged to the formatter for the
    implementing type — see the table of built-in implementations
    in the module documentation for which formatter handles each
    type, and that formatter's documentation for its option set.

  * `:locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0` and is accepted by every
    implementation. The default is `Localize.get_locale/0`.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, exception}` if formatting fails.

  ### Examples

      iex> Localize.Chars.to_string(1234.5, locale: :de)
      {:ok, "1.234,5"}

      iex> Localize.Chars.to_string(~D[2025-07-10], locale: :en)
      {:ok, "Jul 10, 2025"}

  """
  @spec to_string(t(), Keyword.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def to_string(value, options)
end

# ── Fallback implementation ─────────────────────────────────────
#
# Any type without a Localize-specific impl falls through to
# `Kernel.to_string/1`, which dispatches via `String.Chars`. This
# means atoms, charlists, booleans, and `nil` work the same way
# under `Localize.to_string/1` as they do under `Kernel.to_string/1`.
# Types with no `String.Chars` impl (tuples, plain maps, PIDs,
# references, anonymous functions) raise the same
# `Protocol.UndefinedError` they would from `Kernel.to_string/1`.

defimpl Localize.Chars, for: Any do
  def to_string(value), do: {:ok, Kernel.to_string(value)}
  def to_string(value, _options), do: {:ok, Kernel.to_string(value)}
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
  # Charlists (e.g. `~c"hello"` = `[104, 101, 108, 108, 111]`) are
  # treated as strings and converted via `Kernel.to_string/1`,
  # mirroring how `String.Chars`'s `List` impl handles them.
  # Anything else is formatted as a localized list-join.

  def to_string(value), do: do_to_string(value, [])
  def to_string(value, options), do: do_to_string(value, options)

  defp do_to_string(list, options) do
    if list != [] and List.ascii_printable?(list) do
      {:ok, Kernel.to_string(list)}
    else
      Localize.List.to_string(list, options)
    end
  end
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
