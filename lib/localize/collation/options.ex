defmodule Localize.Collation.Options do
  @moduledoc """
  Collation options corresponding to BCP47 -u- extension keys.

  Supports both Elixir keyword list construction and parsing from
  BCP47 locale strings (e.g., "en-u-co-phonebk-ks-level2").

  """

  import Localize.Utils.Helpers, only: [is_keyword_list: 1]

  defstruct strength: :tertiary,
            alternate: :non_ignorable,
            backwards: false,
            normalization: false,
            case_level: false,
            case_first: false,
            numeric: false,
            reorder: [],
            suppress_contractions: [],
            max_variable: :punct,
            type: :standard,
            tailoring: nil,
            han_ordering: :implicit,
            backend: :elixir

  @closed_values [
    strength: [:primary, :secondary, :tertiary, :quaternary, :identical],
    alternate: [:non_ignorable, :shifted],
    backwards: [false, true],
    normalization: [false, true],
    case_level: [false, true],
    case_first: [false, :upper, :lower],
    numeric: [false, true],
    max_variable: [:space, :punct, :symbol, :currency]
  ]

  @type strength :: :primary | :secondary | :tertiary | :quaternary | :identical
  @type alternate :: :non_ignorable | :shifted
  @type case_first_opt :: :upper | :lower | false
  @type max_variable :: :space | :punct | :symbol | :currency
  @type backend :: :nif | :elixir

  @type t :: %__MODULE__{
          strength: strength(),
          alternate: alternate(),
          backwards: boolean(),
          normalization: boolean(),
          case_level: boolean(),
          case_first: case_first_opt(),
          numeric: boolean(),
          reorder: [atom()],
          suppress_contractions: [non_neg_integer()],
          max_variable: max_variable(),
          type: atom(),
          tailoring: map() | nil,
          han_ordering: :implicit | :radical_stroke,
          backend: backend()
        }

  @doc """
  Create a new options struct from a keyword list.

  ### Arguments

  * `options` - a keyword list of collation options (default: `[]`).

  ### Options

  * `:strength` - `:primary`, `:secondary`, `:tertiary` (default), `:quaternary`, or `:identical`.

  * `:alternate` - `:non_ignorable` (default) or `:shifted`.

  * `:backwards` - `false` (default) or `true`.

  * `:normalization` - `false` (default) or `true`.

  * `:case_level` - `false` (default) or `true`.

  * `:case_first` - `false` (default), `:upper`, or `:lower`.

  * `:numeric` - `false` (default) or `true`.

  * `:reorder` - a script code atom or list of script code atoms (default: `[]`).

  * `:max_variable` - `:space`, `:punct` (default), `:symbol`, or `:currency`.

  * `:type` - `:standard` (default), `:search`, `:phonebook`, etc.

  * `:ignore_accents` - `true` to ignore accent differences (sets `strength: :primary`).

  * `:ignore_case` - `true` to ignore case differences (sets `strength: :secondary`).

  * `:ignore_punctuation` - `true` to ignore punctuation and whitespace.

  * `:casing` - `:sensitive` or `:insensitive` (convenience alias for strength).

  * `:backend` - `:nif` or `:elixir`. The default is `:elixir`.

  ### Returns

  * A `%Localize.Collation.Options{}` struct.

  * `{:error, exception}` if `options` is not a keyword list or an
    option's value is not one of those listed above.

  ### Examples

      iex> Localize.Collation.Options.new()
      %Localize.Collation.Options{strength: :tertiary, alternate: :non_ignorable}

      iex> Localize.Collation.Options.new(strength: :primary, alternate: :shifted)
      %Localize.Collation.Options{strength: :primary, alternate: :shifted}

  """
  @spec new(keyword()) :: t() | {:error, Exception.t()}
  def new(options \\ [])

  def new(options) when is_keyword_list(options) do
    with {:ok, options} <- resolve_casing(resolve_shorthands(options)),
         :ok <- validate_values(options) do
      struct(__MODULE__, Keyword.update(options, :reorder, [], &List.wrap/1))
    end
  end

  def new(options), do: {:error, Localize.Utils.Helpers.invalid_options(options)}

  # An option with a closed set of values must take one of them and
  # `:reorder` must be script codes. Other entries pass through to
  # `struct/2`, which ignores keys that are not fields.
  defp validate_values([]), do: :ok

  for {key, values} <- @closed_values do
    defp validate_values([{unquote(key), value} | rest]) when value in unquote(values),
      do: validate_values(rest)

    defp validate_values([{unquote(key), value} | _rest]) do
      {:error,
       Localize.InvalidValueError.exception(
         value: value,
         expected: unquote(key),
         allowed_values: unquote(values)
       )}
    end
  end

  defp validate_values([{:reorder, codes} | rest]) do
    case script_codes(List.wrap(codes)) do
      :ok ->
        validate_values(rest)

      :error ->
        {:error,
         Localize.InvalidValueError.exception(
           value: codes,
           expected: "a script code or a list of script codes",
           context: "the :reorder option"
         )}
    end
  end

  defp validate_values([_other | rest]), do: validate_values(rest)

  defp script_codes([]), do: :ok
  defp script_codes([code | rest]) when is_atom(code) or is_binary(code), do: script_codes(rest)
  defp script_codes(_other), do: :error

  defp resolve_shorthands(options) do
    options
    |> resolve_ignore_accents()
    |> resolve_ignore_case()
    |> resolve_ignore_punctuation()
  end

  defp resolve_ignore_accents(options) do
    case Keyword.pop(options, :ignore_accents) do
      {true, options} ->
        if Keyword.has_key?(options, :strength),
          do: options,
          else: Keyword.put(options, :strength, :primary)

      {_, options} ->
        options
    end
  end

  defp resolve_ignore_case(options) do
    case Keyword.pop(options, :ignore_case) do
      {true, options} ->
        if Keyword.has_key?(options, :strength),
          do: options,
          else: Keyword.put(options, :strength, :secondary)

      {_, options} ->
        options
    end
  end

  defp resolve_ignore_punctuation(options) do
    case Keyword.pop(options, :ignore_punctuation) do
      {true, options} ->
        options
        |> put_default(:strength, :tertiary)
        |> put_default(:alternate, :shifted)

      {_, options} ->
        options
    end
  end

  defp put_default(options, key, value) do
    if Keyword.has_key?(options, key) do
      options
    else
      Keyword.put(options, key, value)
    end
  end

  defp resolve_casing(options) do
    case Keyword.pop(options, :casing) do
      {nil, options} ->
        {:ok, options}

      {:insensitive, options} ->
        {:ok, Keyword.put_new(options, :strength, :secondary)}

      {:sensitive, options} ->
        {:ok, options}

      {other, _options} ->
        {:error,
         Localize.InvalidValueError.exception(
           value: other,
           expected: :casing,
           allowed_values: [:sensitive, :insensitive]
         )}
    end
  end

  @doc """
  Parse collation options from a BCP47 locale string with `-u-` extension.

  ### Arguments

  * `locale` - a BCP47 locale string (e.g., `"en-u-co-phonebk-ks-level2"`).

  ### Returns

  A `%Localize.Collation.Options{}` struct with parsed values.

  ### Examples

      iex> options = Localize.Collation.Options.from_locale("en-u-ks-level2")
      iex> options.strength
      :secondary

      iex> options = Localize.Collation.Options.from_locale("da")
      iex> options.case_first
      :upper

  """
  @spec from_locale(String.t() | atom() | Localize.LanguageTag.t()) ::
          t() | {:error, Exception.t()}
  def from_locale(locale)
      when is_binary(locale) or is_atom(locale) or is_struct(locale, Localize.LanguageTag) do
    # Validation resolves legacy aliases (`"iw"` → `"he"`), POSIX separators
    # and the `-u-` keywords, so a string, an atom and an equivalent tag all
    # yield the same options, read from the tag and never from its text.
    with {:ok, language_tag} <- Localize.validate_locale(locale) do
      from_tag(language_tag)
    end
  end

  def from_locale(locale), do: {:error, Localize.InvalidLocaleError.exception(locale_id: locale)}

  # The tailoring is the tag's CLDR locale's, found by its `cldr_locale_id`
  # and then its parents'; the defaults are its language's; the keywords
  # are its decoded `-u-` extension. Nothing is read from the locale's text.
  defp from_tag(%Localize.LanguageTag{} = language_tag) do
    u_options = u_options(language_tag.locale)

    type =
      Keyword.get(u_options, :type) ||
        Localize.Collation.Tailoring.LocaleDefaults.default_type(language_tag)

    {tailoring_overlay, tailoring_option_overrides} =
      case Localize.Collation.Tailoring.get_tailoring(language_tag, type) do
        {overlay, overrides} -> {overlay, overrides}
        nil -> {nil, []}
      end

    new()
    |> struct(tailoring_option_overrides)
    |> struct(Localize.Collation.Tailoring.LocaleDefaults.options_for(language_tag))
    |> struct(u_options)
    |> Map.put(:tailoring, tailoring_overlay)
  end

  @doc false
  # The collation options a tag's `-u-` extension carries, as validation
  # decoded them: `ks-level2` is `:secondary`, `co-phonebk` `:phonebook`,
  # `kr-latn-digit` `[:Latn, :digit]`, and a boolean keyword `:yes` or `:no`.
  # `Localize.Collation` reads a tag's options with this as well.
  def u_options(%Localize.LanguageTag.U{} = u) do
    []
    |> maybe_put(:type, u.co)
    |> maybe_put(:strength, u.ks)
    |> maybe_put(:alternate, u.ka)
    |> maybe_put(:backwards, u_boolean(u.kb))
    |> maybe_put(:normalization, u_boolean(u.kk))
    |> maybe_put(:case_level, u_boolean(u.kc))
    |> maybe_put(:case_first, u_case_first(u.kf))
    |> maybe_put(:numeric, u_boolean(u.kn))
    |> maybe_put(:reorder, u.kr)
    |> maybe_put(:max_variable, u.kv)
  end

  def u_options(_no_extension) do
    []
  end

  defp u_boolean(:yes) do
    true
  end

  defp u_boolean(:no) do
    false
  end

  defp u_boolean(_unset) do
    nil
  end

  # `kf-false` decodes to `:no`, which `:case_first` writes as `false`.
  defp u_case_first(:no) do
    false
  end

  defp u_case_first(value) do
    value
  end

  defp maybe_put(options, _key, nil) do
    options
  end

  defp maybe_put(options, key, value) do
    Keyword.put(options, key, value)
  end

  @doc """
  Returns whether the given options can be handled by the NIF backend.

  ### Arguments

  * `options` - a `%Localize.Collation.Options{}` struct.

  ### Returns

  * `true` if the NIF backend can handle these options.

  * `false` if the pure Elixir backend is required.

  ### Examples

      iex> Localize.Collation.Options.nif_compatible?(%Localize.Collation.Options{})
      true

      iex> Localize.Collation.Options.nif_compatible?(%Localize.Collation.Options{numeric: true})
      true

  """
  @spec nif_compatible?(t()) :: boolean()
  def nif_compatible?(%__MODULE__{} = options) do
    Localize.Collation.Nif.reorder_codes_supported?(options.reorder) and
      options.max_variable == :punct and
      options.tailoring == nil
  end

  def nif_compatible?(_options), do: false
end
