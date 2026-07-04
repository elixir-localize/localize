defmodule Localize.Exception do
  @moduledoc """
  Conventions and a small behaviour shared by structured Localize
  exceptions.

  ## The `:reason` field

  Exceptions that distinguish between multiple failure categories
  carry a `:reason` field whose value is a **documented atom** from
  a closed set. Callers can pattern-match on `:reason` to branch on
  category without parsing the rendered message; `message/1` is the
  single place a user-facing sentence is assembled.

  Modules that adopt this convention declare `@behaviour
  Localize.Exception` and implement `reason_atoms/0`, returning the
  exhaustive list of valid `:reason` values for that struct. This
  lets tooling — including the structural-exception test suite —
  iterate the documented reasons and verify that `message/1` has a
  clause for each.

  ## The `:cause` field

  When a higher layer must report a lower layer's failure, the outer
  exception carries the inner one in a `:cause` field of type
  `Exception.t() | nil`. The convention is:

  * `:cause` is set when, and only when, the outer exception is a
    wrapper. A direct error sets `:cause` to `nil`.

  * The outer `message/1` may delegate to the inner via
    `Exception.message(cause)`, possibly with a leading context
    phrase.

  * Programmatic callers can pattern-match on the outer struct for
    the operation context, and call `Exception.message/1` on
    `:cause` for the original detail.

  This convention is used by `Localize.FormatError`,
  `Localize.LocaleDownloadError`, and `Localize.ParseError`.

  ## Why no prose in structural fields

  Fields like `:reason`, `:expected`, `:path`, and `:detail` must
  hold structured values — atoms, paths, short labels, struct
  references — not free-form sentences with interpolated values.
  Putting a sentence in a structural field defeats pattern matching,
  duplicates content into `message/1`, and prevents translation.

  """

  @doc """
  Returns the closed set of atoms permitted in this exception's
  `:reason` field.

  Used by tests to verify that `message/1` has a rendering clause
  for each documented reason atom. The list MUST be exhaustive —
  any atom assigned to `:reason` at runtime must appear here.

  """
  @callback reason_atoms() :: [atom()]

  @doc """
  Render an MF2-format Gettext message safely for use inside an
  exception's `message/1` callback.

  `Exception.message/1` is called from `raise`, `Exception.format/2`,
  log handlers, and inspect paths — none of which can tolerate a
  raise. This helper wraps `Gettext.dpgettext/5` so that any failure
  in the message formatter (a NIF crash, a hostile `String.Chars` or
  `Inspect` impl on a bound value, a future regression) falls back
  to the raw msgid rather than propagating.

  Use this only in `defexception` `message/1` callbacks. General MF2
  formatting should call `Gettext.dpgettext/5` (or the higher-level
  macros) directly so callers see the underlying formatter error.

  ### Arguments

  * `msgctxt` is the gettext context string (e.g. `"locale"`).

  * `msgid` is the source-language MF2 message string.

  * `bindings` is a keyword list of variable bindings for the
    message. The default is `[]`.

  ### Returns

  * The interpolated message string, or `msgid` unchanged if
    interpolation failed.

  ### Examples

      iex> Localize.Exception.safe_message("number", "Could not parse {$input}", input: "abc")
      "Could not parse abc"

  """
  @spec safe_message(binary(), binary(), keyword()) :: binary()
  def safe_message(msgctxt, msgid, bindings \\ [])
      when is_binary(msgctxt) and is_binary(msgid) and is_list(bindings) do
    Gettext.dpgettext(Localize.Gettext, "localize", msgctxt, msgid, bindings)
  rescue
    _exception -> msgid
  catch
    _kind, _reason -> msgid
  end
end
