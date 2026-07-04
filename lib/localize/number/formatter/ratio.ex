defmodule Localize.Number.Formatter.Ratio do
  @moduledoc """
  Formats numbers as rational fractions using CLDR rational format patterns.

  Rational fractions contain a numerator and denominator (e.g., ½) and
  may also have an integer part (e.g., 5½). The formatter supports
  three rendering preferences:

  * `:default` — fraction slash with visible space between integer
    and fraction (e.g., "5 1⁄2").

  * `:super_sub` — superscript numerator and subscript denominator
    with zero-width joiner (e.g., "5⁠¹⁄₂").

  * `:precomposed` — Unicode vulgar fraction characters when
    available (e.g., "5½").

  """

  alias Localize.Substitution

  @superscript_map %{
    "0" => "⁰",
    "1" => "¹",
    "2" => "²",
    "3" => "³",
    "4" => "⁴",
    "5" => "⁵",
    "6" => "⁶",
    "7" => "⁷",
    "8" => "⁸",
    "9" => "⁹"
  }

  @subscript_map %{
    "0" => "₀",
    "1" => "₁",
    "2" => "₂",
    "3" => "₃",
    "4" => "₄",
    "5" => "₅",
    "6" => "₆",
    "7" => "₇",
    "8" => "₈",
    "9" => "₉"
  }

  @precomposed_map %{
    {1, 4} => "¼",
    {1, 2} => "½",
    {1, 7} => "⅐",
    {1, 9} => "⅑",
    {1, 10} => "⅒",
    {1, 3} => "⅓",
    {2, 3} => "⅔",
    {1, 5} => "⅕",
    {2, 5} => "⅖",
    {3, 5} => "⅗",
    {4, 5} => "⅘",
    {1, 6} => "⅙",
    {5, 6} => "⅚",
    {1, 8} => "⅛",
    {3, 8} => "⅜",
    {5, 8} => "⅝",
    {7, 8} => "⅞",
    {3, 4} => "¾"
  }

  @doc """
  Formats a number as a rational fraction string.

  ### Arguments

  * `number` is an integer, float, or Decimal.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is
    `Localize.get_locale()`.

  * `:prefer` is a list of rendering preferences. Valid values
    are `:default`, `:super_sub`, and `:precomposed`. The default
    is `[:default]`.

  * `:max_denominator` is the largest permitted denominator.
    The default is `10`.

  * `:max_iterations` is the maximum number of continued fraction
    iterations. The default is `20`.

  * `:epsilon` is the tolerance for float comparisons. The default
    is `1.0e-10`.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, exception}` if the number cannot be converted to
    a ratio or locale data is unavailable.

  ### Examples

      iex> Localize.Number.Formatter.Ratio.to_ratio_string(0.5, locale: :en)
      {:ok, "1⁄2"}

      iex> Localize.Number.Formatter.Ratio.to_ratio_string(3.25, locale: :en)
      {:ok, "3\u202F1⁄4"}

  """
  @spec to_ratio_string(number() | Decimal.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def to_ratio_string(number, options \\ []) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    prefer = List.wrap(Keyword.get(options, :prefer, [:default]))

    ratio_options = [
      max_denominator: Keyword.get(options, :max_denominator, 10),
      max_iterations: Keyword.get(options, :max_iterations, 20),
      epsilon: Keyword.get(options, :epsilon, 1.0e-10)
    ]

    number_options = Keyword.put_new(options, :locale, locale)

    with {:ok, language_tag} <- Localize.validate_locale(locale),
         {:ok, number_system} <- Localize.Number.System.number_system_from_locale(language_tag),
         {:ok, formats} <- Localize.Number.Format.formats_for(language_tag, number_system),
         {:ok, rational_formats} <- extract_rational_formats(formats, language_tag) do
      float_number = to_float(number)

      case number_to_integer_and_fraction(float_number) do
        {integer, fraction} when integer == 0 and fraction == +0.0 ->
          Localize.Number.to_string(number, number_options)

        {0, fraction} ->
          format_fraction(fraction, rational_formats, prefer, ratio_options, number_options)

        {integer, +0.0} ->
          Localize.Number.to_string(integer, number_options)

        {integer, fraction} ->
          format_integer_and_fraction(
            integer,
            fraction,
            rational_formats,
            prefer,
            ratio_options,
            number_options
          )
      end
    end
  end

  # ── Private helpers ──────────────────────────────────────────

  defp extract_rational_formats(%{rational: nil}, language_tag) do
    {:error,
     Localize.ItemNotFoundError.exception(
       locale: language_tag,
       keys: [:rational]
     )}
  end

  defp extract_rational_formats(%{rational: rational}, _language_tag) do
    {:ok, rational}
  end

  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(number) when is_float(number), do: number
  defp to_float(number) when is_integer(number), do: number * 1.0

  defp number_to_integer_and_fraction(number) when is_float(number) do
    integer = trunc(number)
    fraction = number - integer
    {integer, fraction}
  end

  defp format_integer_and_fraction(
         integer,
         fraction,
         formats,
         prefer,
         ratio_options,
         number_options
       ) do
    # For the fraction part of a negative number, force positive display
    fraction_options =
      if integer > 0, do: number_options, else: number_options

    with {:ok, integer_string} <- Localize.Number.to_string(integer, number_options),
         {:ok, fraction_string} <-
           format_fraction(abs(fraction), formats, prefer, ratio_options, fraction_options) do
      pattern =
        if :super_sub in prefer,
          do: formats.integer_and_rational_pattern.super_sub,
          else: formats.integer_and_rational_pattern.default

      result = Substitution.substitute([integer_string, fraction_string], pattern)
      {:ok, IO.iodata_to_binary(result)}
    end
  end

  defp format_fraction(fraction, formats, prefer, ratio_options, number_options) do
    case Localize.Utils.Math.float_to_ratio(abs(fraction), ratio_options) do
      {numerator, denominator} ->
        prefer_precomposed? = :precomposed in prefer

        format_ratio(
          {numerator, denominator},
          formats,
          prefer,
          number_options,
          prefer_precomposed?
        )

      _other ->
        {:error,
         Localize.InvalidValueError.exception(
           value: fraction,
           expected: "a number convertible to a ratio",
           context: "Localize.Number.Formatter.Ratio.to_ratio_string/2"
         )}
    end
  end

  defp format_ratio({numerator, denominator}, _formats, _prefer, _number_options, true)
       when is_map_key(@precomposed_map, {numerator, denominator}) do
    {:ok, Map.fetch!(@precomposed_map, {numerator, denominator})}
  end

  defp format_ratio({numerator, denominator}, formats, prefer, number_options, _precomposed?) do
    with {:ok, numerator_string} <- Localize.Number.to_string(numerator, number_options),
         {:ok, denominator_string} <- Localize.Number.to_string(abs(denominator), number_options) do
      fraction_parts =
        [numerator_string, denominator_string]
        |> maybe_apply_super_subscript(:super_sub in prefer)

      pattern = formats.rational_pattern.default
      result = Substitution.substitute(fraction_parts, pattern)
      {:ok, IO.iodata_to_binary(result)}
    end
  end

  defp maybe_apply_super_subscript(parts, false), do: parts

  defp maybe_apply_super_subscript([numerator, denominator], true) do
    [map_superscript(numerator), map_subscript(denominator)]
  end

  defp map_superscript(string) do
    string
    |> String.graphemes()
    |> Enum.map(fn grapheme -> Map.get(@superscript_map, grapheme, grapheme) end)
    |> IO.iodata_to_binary()
  end

  defp map_subscript(string) do
    string
    |> String.graphemes()
    |> Enum.map(fn grapheme -> Map.get(@subscript_map, grapheme, grapheme) end)
    |> IO.iodata_to_binary()
  end
end
