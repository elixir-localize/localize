defmodule Localize.DateRangeParseError do
  @moduledoc """
  Returned (or raised) by `Localize.Interval.parse/2` when an
  input cannot be interpreted as a date range, or when both
  endpoints parsed successfully but the resulting range is invalid.

  Carries semantic fields only; the human-readable description is
  materialised by `message/1`. Pattern-match on `:reason` to branch
  on failure category without parsing prose.

  ### Fields

  * `:input` — the raw input that was passed in. A binary for the
    single-string form, a `{from, to}` tuple for the pair form.

  * `:reason` — atom describing the failure category. See
    `reason_atoms/0` for the closed set of permitted values.

  * `:locale` — the locale the parser tried. Set for failures
    surfaced before sub-parsing (e.g. `:no_separator`).

  * `:from`, `:to` — the parsed endpoints. Set when the failure
    occurs after both endpoints parsed successfully
    (e.g. `:inverted`).

  * `:cause` — the wrapped inner exception when this error is a
    wrapper for a sub-parser failure (`:from_parse_failed` /
    `:to_parse_failed`). `nil` otherwise.

  """

  @behaviour Localize.Exception

  defexception [:input, :reason, :locale, :from, :to, :cause]

  @type reason ::
          :no_separator
          | :inverted
          | :from_parse_failed
          | :to_parse_failed

  @type t :: %__MODULE__{
          input: term(),
          reason: reason() | nil,
          locale: atom() | String.t() | nil,
          from: Date.t() | nil,
          to: Date.t() | nil,
          cause: Exception.t() | nil
        }

  @impl Localize.Exception
  def reason_atoms,
    do: [:no_separator, :inverted, :from_parse_failed, :to_parse_failed]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{reason: :no_separator, input: input, locale: locale}) do
    "could not find an interval separator in #{inspect(input)} for locale " <>
      "#{inspect(locale)}; expected CLDR interval-fallback separator (e.g. \" – \") " <>
      "or one of `-`, `/`, `~`, `〜`"
  end

  def message(%__MODULE__{reason: :inverted, from: from, to: to}) do
    "range end #{inspect(to)} is before start #{inspect(from)}; " <>
      "pass `allow_inverted: true` to permit descending ranges"
  end

  def message(%__MODULE__{reason: reason, input: input, cause: cause})
      when reason in [:from_parse_failed, :to_parse_failed] do
    endpoint = if reason == :from_parse_failed, do: "from", else: "to"
    cause_suffix = if cause, do: ": " <> Exception.message(cause), else: ""
    "range #{endpoint}-endpoint #{inspect(input)} could not be parsed" <> cause_suffix
  end

  def message(%__MODULE__{input: input}) do
    "could not parse #{inspect(input)} as a date range"
  end
end
