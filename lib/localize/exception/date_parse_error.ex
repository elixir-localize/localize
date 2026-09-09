defmodule Localize.DateParseError do
  @moduledoc """
  Returned (or raised) by `Localize.Date.parse/2` when an input
  string cannot be interpreted as a date.

  Carries semantic fields only; the human-readable description is
  materialised by `message/1` so callers can pattern-match on
  structure (input/locale/calendar) without parsing prose.

  ### Fields

  * `:input` — the raw string that failed to parse.

  * `:locale` — the locale the parser tried.

  * `:calendar` — the CLDR calendar key the parser tried.

  """

  defexception [:input, :locale, :calendar]

  @type t :: %__MODULE__{
          input: String.t() | nil,
          locale: atom() | String.t() | nil,
          calendar: atom() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{input: input, locale: locale, calendar: calendar}) do
    "could not parse #{inspect(input)} as a date in locale #{inspect(locale)} " <>
      "(calendar #{inspect(calendar)}); ISO-8601 (YYYY-MM-DD) is always accepted as a fallback"
  end
end
