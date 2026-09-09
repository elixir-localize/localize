defmodule Localize.TimeParseError do
  @moduledoc """
  Returned (or raised) by `Localize.Time.parse/2` when an input
  string cannot be interpreted as a time.

  Carries semantic fields only; the human-readable description is
  materialised by `message/1` so callers can pattern-match on
  structure (input/locale) without parsing prose.

  ### Fields

  * `:input` — the raw string that failed to parse.

  * `:locale` — the locale the parser tried.

  """

  defexception [:input, :locale]

  @type t :: %__MODULE__{
          input: String.t() | nil,
          locale: atom() | String.t() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{input: input, locale: locale}) do
    "could not parse #{inspect(input)} as a time in locale #{inspect(locale)}; " <>
      "ISO-8601 (HH:MM[:SS[.frac]]) is always accepted as a fallback"
  end
end
