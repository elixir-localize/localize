defmodule Localize.Collation.Options do
  @moduledoc """
  Collation options corresponding to BCP47 -u- extension keys.

  Supports both Elixir keyword list construction and parsing from
  BCP47 locale strings (e.g., "en-u-co-phonebk-ks-level2").

  """

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

  A `%Localize.Collation.Options{}` struct.

  ### Examples

      iex> Localize.Collation.Options.new()
      %Localize.Collation.Options{strength: :tertiary, alternate: :non_ignorable}

      iex> Localize.Collation.Options.new(strength: :primary, alternate: :shifted)
      %Localize.Collation.Options{strength: :primary, alternate: :shifted}

  """
  @spec new(keyword()) :: t()
  def new(options \\ []) do
    options =
      options
      |> resolve_ignore_accents()
      |> resolve_ignore_case()
      |> resolve_ignore_punctuation()
      |> resolve_casing()
      |> Keyword.update(:reorder, [], &List.wrap/1)

    struct(__MODULE__, options)
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
        |> then(fn opts ->
          if Keyword.has_key?(opts, :strength),
            do: opts,
            else: Keyword.put(opts, :strength, :tertiary)
        end)
        |> then(fn opts ->
          if Keyword.has_key?(opts, :alternate),
            do: opts,
            else: Keyword.put(opts, :alternate, :shifted)
        end)

      {_, options} ->
        options
    end
  end

  defp resolve_casing(options) do
    case Keyword.pop(options, :casing) do
      {nil, options} ->
        options

      {:insensitive, options} ->
        if Keyword.has_key?(options, :strength) do
          options
        else
          Keyword.put(options, :strength, :secondary)
        end

      {:sensitive, options} ->
        options

      {other, _options} ->
        raise Localize.InvalidValueError.exception(
                value: other,
                expected: :casing,
                allowed_values: [:sensitive, :insensitive]
              )
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
  @spec from_locale(String.t()) :: t()
  def from_locale(locale) when is_binary(locale) do
    alias Localize.Collation.Tailoring
    alias Localize.Collation.Tailoring.LocaleDefaults

    language = LocaleDefaults.extract_language(locale)
    locale_defaults = LocaleDefaults.options_for(locale)
    u_pairs = extract_u_extension(locale)
    bcp47_opts = if u_pairs, do: u_pairs_to_opts(u_pairs), else: []

    type = Keyword.get(bcp47_opts, :type, LocaleDefaults.default_type(locale))

    {tailoring_overlay, tailoring_option_overrides} =
      case Tailoring.get_tailoring(language, type) do
        {overlay, overrides} -> {overlay, overrides}
        nil -> {nil, []}
      end

    new()
    |> struct(tailoring_option_overrides)
    |> struct(locale_defaults)
    |> struct(bcp47_opts)
    |> Map.put(:tailoring, tailoring_overlay)
  end

  defp u_pairs_to_opts(pairs) do
    Enum.reduce(pairs, [], fn {key, value}, acc ->
      case key do
        "co" -> [{:type, parse_type(value)} | acc]
        "ks" -> [{:strength, parse_strength(value)} | acc]
        "ka" -> [{:alternate, parse_alternate(value)} | acc]
        "kb" -> [{:backwards, parse_bool(value)} | acc]
        "kk" -> [{:normalization, parse_bool(value)} | acc]
        "kc" -> [{:case_level, parse_bool(value)} | acc]
        "kf" -> [{:case_first, parse_case_first(value)} | acc]
        "kn" -> [{:numeric, parse_bool(value)} | acc]
        "kr" -> [{:reorder, parse_reorder_codes(value)} | acc]
        "kv" -> [{:max_variable, parse_max_variable(value)} | acc]
        _ -> acc
      end
    end)
  end

  defp extract_u_extension(locale) do
    parts = String.split(locale, "-")

    case Enum.find_index(parts, &(&1 == "u")) do
      nil ->
        nil

      idx ->
        parts
        |> Enum.drop(idx + 1)
        |> collect_pairs([])
    end
  end

  defp collect_pairs([], acc), do: Enum.reverse(acc)

  defp collect_pairs([<<c::utf8>> | _rest], acc)
       when c in ?a..?z and c != ?u do
    Enum.reverse(acc)
  end

  defp collect_pairs([key, value | rest], acc) when byte_size(key) == 2 do
    collect_pairs(rest, [{key, value} | acc])
  end

  defp collect_pairs([key | rest], acc) when byte_size(key) == 2 do
    collect_pairs(rest, [{key, "true"} | acc])
  end

  defp collect_pairs([value | rest], acc) do
    case acc do
      [{key, prev_val} | acc_rest] ->
        collect_pairs(rest, [{key, prev_val <> "-" <> value} | acc_rest])

      _ ->
        collect_pairs(rest, acc)
    end
  end

  defp parse_strength("level1"), do: :primary
  defp parse_strength("level2"), do: :secondary
  defp parse_strength("level3"), do: :tertiary
  defp parse_strength("level4"), do: :quaternary
  defp parse_strength("identic"), do: :identical
  defp parse_strength(_), do: :tertiary

  defp parse_alternate("noignore"), do: :non_ignorable
  defp parse_alternate("shifted"), do: :shifted
  defp parse_alternate(_), do: :non_ignorable

  defp parse_bool("true"), do: true
  defp parse_bool("false"), do: false
  defp parse_bool(_), do: false

  defp parse_case_first("upper"), do: :upper
  defp parse_case_first("lower"), do: :lower
  defp parse_case_first("false"), do: false
  defp parse_case_first(_), do: false

  defp parse_max_variable("space"), do: :space
  defp parse_max_variable("punct"), do: :punct
  defp parse_max_variable("symbol"), do: :symbol
  defp parse_max_variable("currency"), do: :currency
  defp parse_max_variable(_), do: :punct

  defp parse_type("standard"), do: :standard
  defp parse_type("search"), do: :search
  defp parse_type("phonebk"), do: :phonebook
  defp parse_type("pinyin"), do: :pinyin
  defp parse_type("stroke"), do: :stroke
  defp parse_type("unihan"), do: :unihan
  defp parse_type("zhuyin"), do: :zhuyin
  defp parse_type("searchjl"), do: :searchjl
  defp parse_type("eor"), do: :eor
  defp parse_type("trad"), do: :traditional
  defp parse_type("tradnl"), do: :traditional

  # Unknown collation types from a `-u-co-` extension default to
  # `:standard`. Previously this fallthrough called `String.to_atom/1`
  # on the raw value, growing the atom table for every distinct
  # attacker-supplied collation name. Tailoring lookup with an
  # unknown type already produces nil → no tailoring overlay, which
  # is the same end state as `:standard` for an unrecognised type.
  defp parse_type(_other), do: :standard

  # Parse `-u-kr-` reorder code list. Codes are script names (e.g.
  # `latn`, `cyrl`) or category names (e.g. `digit`, `currency`).
  # Use `existing_atom/1` so attacker-supplied codes can't grow the
  # atom table; unknown codes are dropped silently (the consumer
  # uses the list as a Map.get key, where nil entries miss).
  defp parse_reorder_codes(value) when is_binary(value) do
    value
    |> String.split("-")
    |> Enum.map(&Localize.Utils.Helpers.existing_atom/1)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Return the maximum primary weight that counts as "variable" for the given setting.

  ### Arguments

  * `options` - a `%Localize.Collation.Options{}` struct.

  ### Returns

  A non-negative integer representing the maximum primary weight boundary.

  ### Examples

      iex> Localize.Collation.Options.max_variable_primary(%Localize.Collation.Options{max_variable: :punct})
      0x0B61

      iex> Localize.Collation.Options.max_variable_primary(%Localize.Collation.Options{max_variable: :space})
      0x0209

  """
  @spec max_variable_primary(t()) :: non_neg_integer()
  def max_variable_primary(%__MODULE__{max_variable: :space}), do: 0x0209
  def max_variable_primary(%__MODULE__{max_variable: :punct}), do: 0x0B61
  def max_variable_primary(%__MODULE__{max_variable: :symbol}), do: 0x0EE3
  def max_variable_primary(%__MODULE__{max_variable: :currency}), do: 0x0EFF

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
end
