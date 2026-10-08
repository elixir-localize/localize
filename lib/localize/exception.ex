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
  log handlers, and inspect paths. This helper asks the Gettext
  backend for the message directly, as a tagged result, so a message
  the formatter cannot complete — a missing binding, a msgid that is
  not valid MF2 — falls back to the raw msgid rather than raising, as
  `Gettext.dpgettext/5` would.

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

  def safe_message(msgctxt, msgid, bindings)
      when is_binary(msgctxt) and is_binary(msgid) and is_list(bindings) do
    if Keyword.keyword?(bindings) do
      locale = Gettext.get_locale(Localize.Gettext)

      case Localize.Gettext.lgettext(locale, "localize", msgctxt, msgid, Map.new(bindings)) do
        {:missing_bindings, _incomplete, _missing} -> msgid
        # `{:ok, translation}`, or `{:default, message}` when the locale
        # has no translation for `msgid`.
        {_translated_or_default, message} -> message
      end
    else
      msgid
    end
  end

  def safe_message(_msgctxt, msgid, _bindings) when is_binary(msgid), do: msgid

  def safe_message(_msgctxt, msgid, _bindings), do: inspect(msgid)

  @doc """
  Normalizes the locale bindings of an exception to locale identifiers.

  A `:locale` or `:locale_id` binding is machine-readable data a caller
  pattern matches on, so it holds a locale identifier. Formatting code
  threads a validated `t:Localize.LanguageTag.t/0` rather than an id, and
  hands that tag to the exception; this replaces such a tag with its
  `:cldr_locale_id` so the binding keeps its contract. Every other binding,
  and a tag that carries no id, is left as it stands.

  ### Arguments

  * `bindings` is the keyword list of bindings given to `exception/1`.

  ### Returns

  * The bindings, with any `:locale` or `:locale_id` language tag replaced
    by its locale identifier.

  ### Examples

      iex> {:ok, language_tag} = Localize.validate_locale("en")
      iex> Localize.Exception.normalize_locale_bindings(locale: language_tag)
      [locale: :en]

      iex> Localize.Exception.normalize_locale_bindings(locale: :fr, other: 1)
      [locale: :fr, other: 1]

  """
  @spec normalize_locale_bindings(keyword()) :: keyword()
  def normalize_locale_bindings(bindings) when is_list(bindings) do
    Enum.map(bindings, fn
      {key, %Localize.LanguageTag{cldr_locale_id: locale_id}}
      when key in [:locale, :locale_id] and not is_nil(locale_id) ->
        {key, locale_id}

      binding ->
        binding
    end)
  end

  def normalize_locale_bindings(bindings), do: bindings

  @doc """
  Renders a locale as a name fit for an exception message.

  A validated locale is a `t:Localize.LanguageTag.t/0`, which inspects as
  the expression that rebuilds it rather than as a locale name. A message
  should name the locale, so a tag renders as its locale id and any other
  value as itself.

  ### Arguments

  * `locale` is a locale identifier atom or string, or a
    `t:Localize.LanguageTag.t/0` in any state of resolution.

  ### Returns

  * A string naming the locale, ready to interpolate into a message.

  ### Examples

      iex> Localize.Exception.locale_name(:en)
      ":en"

      iex> {:ok, language_tag} = Localize.validate_locale("en")
      iex> Localize.Exception.locale_name(language_tag)
      ":en"

  """
  @spec locale_name(Localize.locale() | String.t()) :: String.t()
  def locale_name(%Localize.LanguageTag{cldr_locale_id: locale_id})
      when not is_nil(locale_id) do
    inspect(locale_id)
  end

  def locale_name(%Localize.LanguageTag{canonical_locale_id: locale_id})
      when not is_nil(locale_id) do
    inspect(locale_id)
  end

  def locale_name(%Localize.LanguageTag{requested_locale_id: locale_id})
      when not is_nil(locale_id) do
    inspect(locale_id)
  end

  def locale_name(locale), do: inspect(locale)
end
