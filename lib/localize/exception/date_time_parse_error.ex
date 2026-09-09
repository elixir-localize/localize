defmodule Localize.DateTimeParseError do
  @moduledoc """
  Returned (or raised) when an input string cannot be interpreted as a
  date, a time, a datetime or a date range.

  `Localize.DateTime.parse/2` returns it with `:attempts` unset.
  `Localize.DateTime.Parser.parse/2`, which tries each shape in turn,
  populates `:attempts` with what every sub-parser reported.

  Carries semantic fields only; the human-readable description is
  materialised by `message/1` so callers can pattern-match on
  structure (input/locale) without parsing prose.

  ### Fields

  * `:input` — the raw string that failed to parse.

  * `:locale` — the locale the parser tried.

  * `:attempts` — a keyword list of `{kind, exception}` recording each
    sub-parser that was tried and the exception it returned, in the
    order they were attempted. `kind` is one of `:interval`, `:date`,
    `:time` or `:datetime`. `nil` when a single shape was parsed.

  """

  defexception [:input, :locale, :attempts]

  @type kind :: :interval | :date | :time | :datetime
  @type attempt :: {kind(), Exception.t()}
  @type t :: %__MODULE__{
          input: String.t() | nil,
          locale: atom() | String.t() | nil,
          attempts: [attempt()] | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{input: input, locale: locale, attempts: nil}) do
    "could not parse #{inspect(input)} as a datetime in locale #{inspect(locale)}; " <>
      "ISO-8601 (YYYY-MM-DDTHH:MM:SS[Z|±HH:MM]) is always accepted as a fallback"
  end

  def message(%__MODULE__{input: input, locale: locale}) do
    "could not parse #{inspect(input)} as a date, time, datetime, or " <>
      "interval in locale #{inspect(locale)}"
  end
end
