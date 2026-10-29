defmodule Localize.Number.ParserDifferential do
  @moduledoc false

  # Inputs for, and the comparison behind, the differential test of
  # `Localize.Number.Parser` against `Localize.Number.ReferenceParser`
  # (`plans/number-parser-grammar.md`). The reference is the parser as it
  # stood when the rewrite began; every input below must read the same with
  # both, value for value and error for error.
  #
  # The locales are a sample of fifty-odd that cover every separator set,
  # digit script and currency placement CLDR has, unless
  # `LOCALIZE_DIFFERENTIAL_LOCALES` names others or is `all`. A full run
  # across every installed locale wants `ERL_FLAGS="+MIscs 8192"`, since each
  # locale's parsing tables go into the literal area.

  @parser Localize.Number.Parser
  @reference Localize.Number.ReferenceParser

  @sample_locales ~w(
    en en-US en-GB en-AU en-IN en-150 en-MT en-ZA de de-AT de-CH de-LI fr fr-CA
    fr-CH fr-HT fr-BE it it-CH es es-MX es-AR pt pt-BR pt-PT nl nl-BE da sv nb
    fi pl cs sk hu ru uk bg el tr he ar ar-EG ar-MA ar-SA fa fa-AF ur hi bn ta
    th vi zh zh-Hant zh-Hant-HK ja ko id ms sw af mn my so bem lv lt et sq und
  )

  @styles [
    symbol: [],
    accounting: [format: :accounting],
    iso: [currency_symbol: :iso],
    narrow: [currency_symbol: :narrow],
    long: [format: :long]
  ]

  @amounts ~w(0 1 -1 0.05 12.34 1234.56 -1234567.89 1000000 0.123 -0.5)

  @currencies [:USD, :EUR, :JPY, :GBP, :KWD, :CHF, :INR, :CNY, :BHD, :CAD, :AUD]

  # Hand-picked numbers that exercise one rule each: signs, marks, dashes,
  # spaces, scripts, underscores, exponents and the inputs that are no number.
  @numbers [
    "0",
    "5",
    "-5",
    "+5",
    "5-",
    "- 5",
    "(5)",
    "(-5)",
    "-5-",
    "−5",
    "‎-5",
    ".5",
    "5.",
    "-.5",
    "−.5",
    "+.5",
    "(.5)",
    "5.–",
    "5.--",
    "5,–",
    "1,234.56",
    "1.234,56",
    "1'234.56",
    "1’234.56",
    "1 234,56",
    "1 234,56",
    "1 234,56",
    "1 2",
    "1,2,3",
    "1.2.3",
    "12,345.678",
    "1,23,456.78",
    "12,34,567",
    "१,२३४.५६",
    "١٬٢٣٤٫٥٦",
    "۱۲۳۴",
    "５",
    "1_000",
    "1_000_000.34",
    "_5",
    "5_",
    "1__000",
    "5._5",
    "1e5",
    "1.5E-2",
    "1e400",
    "5²",
    "",
    " ",
    "abc",
    "5 USD",
    "1.599",
    "73,460",
    "0,5",
    "1.23",
    "100.00"
  ]

  @perturbations [
    {"nbsp_to_space", &__MODULE__.nbsp_to_space/1},
    {"space_to_nbsp", &__MODULE__.space_to_nbsp/1},
    {"unicode_minus", &__MODULE__.unicode_minus/1},
    {"ascii_minus", &__MODULE__.ascii_minus/1},
    {"bidi_ends", &__MODULE__.bidi_ends/1},
    {"outer_spaces", &__MODULE__.outer_spaces/1},
    {"downcase_code", &__MODULE__.downcase_code/1},
    {"fullwidth_dollar", &__MODULE__.fullwidth_dollar/1},
    {"swap_separators", &__MODULE__.swap_separators/1},
    {"drop_groups", &__MODULE__.drop_groups/1},
    {"drop_last_mark", &__MODULE__.drop_last_mark/1},
    {"misplace_group", &__MODULE__.misplace_group/1},
    {"trailing_period", &__MODULE__.trailing_period/1},
    {"trailing_comma", &__MODULE__.trailing_comma/1},
    {"doubled_mark", &__MODULE__.doubled_mark/1},
    {"digit_dropped", &__MODULE__.digit_dropped/1},
    {"underscore_groups", &__MODULE__.underscore_groups/1}
  ]

  @corpus Path.expand("data/currency_amount_corpus.tsv", __DIR__)

  @type input :: {:parse | :parse_currency_amount, String.t(), Keyword.t()}

  @doc "The locales to run across: the sample, or what the environment names."
  @spec locales() :: [String.t()]
  def locales do
    case System.get_env("LOCALIZE_DIFFERENTIAL_LOCALES") do
      nil -> @sample_locales
      "all" -> Enum.map(Localize.all_locale_ids(), &to_string/1)
      names -> String.split(names, ",", trim: true)
    end
  end

  @doc "Every currency amount input: the corpus, formatted amounts, their perturbations and cross-locale readings."
  @spec amount_inputs([String.t()]) :: [input()]
  def amount_inputs(locales) do
    corpus_inputs() ++
      formatted_inputs(locales) ++ perturbed_inputs(locales) ++ cross_inputs(locales)
  end

  @doc "Every number input: formatted numbers in each locale, their variants, and the hand-picked list."
  @spec number_inputs([String.t()]) :: [input()]
  def number_inputs(locales) do
    texts =
      for locale <- locales,
          amount <- @amounts ++ ["1234567.891", "0.000001"],
          {:ok, text} <- [Localize.Number.to_string(Decimal.new(amount), locale: locale)],
          variant <- number_variants(text),
          do: {locale, variant}

    hand = for locale <- locales, number <- @numbers, do: {locale, number}

    for {locale, text} <- Enum.uniq(texts ++ hand),
        options <- number_options(locale),
        do: {:parse, text, options}
  end

  @doc "The inputs the two parsers read differently, as `{input, reference, new}`."
  @spec differences([input()]) :: [{input(), term(), term()}]
  def differences(inputs) do
    inputs
    |> Task.async_stream(&difference/1, ordered: false, timeout: :infinity)
    |> Enum.flat_map(fn {:ok, result} -> result end)
  end

  @doc "A report of the first differences, one per line."
  @spec report([{input(), term(), term()}], pos_integer()) :: String.t()
  def report(differences, limit \\ 40) do
    shown =
      differences
      |> Enum.take(limit)
      |> Enum.map_join("\n", fn {{function, string, options}, reference, new} ->
        "#{function} #{inspect(string)} #{inspect(options)}\n" <>
          "  reference: #{inspect(reference, limit: 8)}\n" <>
          "  new:       #{inspect(new, limit: 8)}"
      end)

    "#{length(differences)} differences\n" <> shown
  end

  # ── Amount inputs ─────────────────────────────────────────────

  defp corpus_inputs do
    @corpus
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "#"))
    |> Enum.map(&String.split(&1, "\t"))
    |> Enum.map(fn [locale, input, _expected, _status, _source | rest] ->
      {:parse_currency_amount, unescape(input), amount_options(locale, Enum.at(rest, 2, ""))}
    end)
  end

  defp formatted_inputs(locales) do
    for {locale, text, _currency} <- formatted(locales, @currencies, @amounts, @styles),
        options <- [[locale: locale], [locale: locale, caller_currency: &token/1]],
        do: {:parse_currency_amount, text, options}
  end

  defp perturbed_inputs(locales) do
    base =
      formatted(locales, [:USD], ~w(1234.56 -1234567.89 0.5 12.34 1000000), symbol: [], iso: [])

    for {_name, transform} <- @perturbations,
        {locale, text, _currency} <- base,
        changed = transform.(text),
        changed != text,
        do: {:parse_currency_amount, changed, [locale: locale]}
  end

  # What one locale writes, read in another: the texts are formatted once
  # and read in every other sampled locale.
  defp cross_inputs(locales) do
    texts = formatted(locales, [:USD], ~w(1234.56 1234567 0.5), iso: [])

    for {writer, text, _currency} <- texts,
        reader <- locales,
        reader != writer,
        do: {:parse_currency_amount, text, [locale: reader]}
  end

  defp formatted(locales, currencies, amounts, styles) do
    for locale <- locales,
        currency <- Enum.uniq(own_currency(locale) ++ currencies),
        amount <- amounts,
        {_style, style_options} <- styles,
        {:ok, text} <-
          [
            Localize.Number.to_string(
              Decimal.new(amount),
              [locale: locale, currency: currency] ++ style_options
            )
          ],
        do: {locale, text, currency}
  end

  defp own_currency(locale) do
    case Localize.Currency.currency_from_locale(locale) do
      {:ok, currency} when is_atom(currency) and not is_nil(currency) -> [currency]
      _no_currency -> []
    end
  end

  defp amount_options(locale, "") do
    [locale: locale]
  end

  defp amount_options(locale, given_currency) do
    [locale: locale, default_currency: given_currency]
  end

  # A caller's currencies, as ex_money names digital tokens: a symbol, two
  # names and an identifier with digits in it.
  @doc false
  def token(text) when text in ["₿", "BTC", "Bitcoin", "4H95J0R2X"] do
    {:ok, "BTC"}
  end

  def token("₮") do
    {:ok, "USDT"}
  end

  def token(_text) do
    :error
  end

  defp unescape(text) do
    Regex.replace(~r/\\u\{([0-9A-Fa-f]{4,6})\}/, text, fn _match, hex ->
      <<String.to_integer(hex, 16)::utf8>>
    end)
  end

  # ── Number inputs ─────────────────────────────────────────────

  defp number_variants(text) do
    [
      text,
      nbsp_to_space(text),
      unicode_minus(text),
      bidi_ends(text),
      outer_spaces(text),
      "(" <> String.trim_leading(text, "-") <> ")",
      String.trim_leading(text, "-") <> "-",
      "+" <> String.trim_leading(text, "-"),
      swap_separators(text),
      drop_groups(text),
      trailing_period(text),
      doubled_mark(text),
      underscore_groups(text)
    ]
  end

  defp number_options(locale) do
    [
      [locale: locale],
      [locale: locale, lenient: false],
      [locale: locale, grouping: :sizes],
      [locale: locale, grouping: :sizes, currency: :EUR],
      [locale: locale, grouping: :sizes, currency: :EUR, root_separators: true],
      [locale: locale, number: :decimal],
      [locale: locale, number: :integer],
      [locale: locale, number: :float],
      [locale: locale, separators: :standard]
    ]
  end

  # ── Perturbations ─────────────────────────────────────────────

  @doc false
  def nbsp_to_space(text) do
    String.replace(text, [" ", " "], " ")
  end

  @doc false
  def space_to_nbsp(text) do
    String.replace(text, " ", " ")
  end

  @doc false
  def unicode_minus(text) do
    String.replace(text, "-", "−")
  end

  @doc false
  def ascii_minus(text) do
    String.replace(text, "−", "-")
  end

  @doc false
  def bidi_ends(text) do
    "‎" <> text <> "‏"
  end

  @doc false
  def outer_spaces(text) do
    "  " <> text <> " "
  end

  @doc false
  def downcase_code(text) do
    Regex.replace(~r/\b[A-Z]{3}\b/, text, &String.downcase/1)
  end

  @doc false
  def fullwidth_dollar(text) do
    String.replace(text, "$", "＄")
  end

  @doc false
  def swap_separators(text) do
    text
    |> String.replace(".", "\u0001")
    |> String.replace(",", ".")
    |> String.replace("\u0001", ",")
  end

  @doc false
  def drop_groups(text) do
    Regex.replace(~r/(?<=\d)[,.'’\x{00A0}\x{202F} ](?=\d{3}(?!\d))/u, text, "")
  end

  @doc false
  def drop_last_mark(text) do
    Regex.replace(~r/(\d)[.,٫](\d+)(?!.*\d)/u, text, "\\1\\2")
  end

  @doc false
  def misplace_group(text) do
    Regex.replace(~r/(\d)(\d)([,.'’\x{00A0}\x{202F}])(\d{3})/u, text, "\\1\\3\\2\\4",
      global: false
    )
  end

  @doc false
  def trailing_period(text) do
    Regex.replace(~r/(\d)(?!.*\d)/u, text, "\\1.")
  end

  @doc false
  def trailing_comma(text) do
    Regex.replace(~r/(\d)(?!.*\d)/u, text, "\\1,")
  end

  @doc false
  def doubled_mark(text) do
    Regex.replace(~r/(\d)([.,])(\d)/u, text, "\\1\\2\\2\\3", global: false)
  end

  @doc false
  def digit_dropped(text) do
    Regex.replace(~r/\d(?=\D*$)/u, text, "")
  end

  @doc false
  def underscore_groups(text) do
    Regex.replace(~r/(?<=\d)[,.'’\x{00A0}\x{202F} ](?=\d{3}(?!\d))/u, text, "_")
  end

  # ── Comparison ────────────────────────────────────────────────

  defp difference({function, string, options} = input) do
    new = call(@parser, function, string, options)
    reference = call(@reference, function, string, options)

    if same?(new, reference) or expected_difference?(input, reference, new) do
      []
    else
      [{input, reference, new}]
    end
  end

  # The gaps the rewrite closes on purpose (`plans/number-parser-grammar.md`,
  # decided 2026-10-29): an underscore anywhere but between two digits,
  # which the reference dropped and the new parser refuses.
  @stray_underscore ~r/(?<!\p{Nd})_|_(?!\p{Nd})/u

  defp expected_difference?({:parse, string, _options}, {:ok, _value}, {:error, _exception}) do
    String.match?(string, @stray_underscore)
  end

  defp expected_difference?(_input, _reference, _new) do
    false
  end

  # A parser that raises is a defect, but one the report should name the
  # input of rather than end the run on.
  defp call(module, function, string, options) do
    isolated =
      Localize.Utils.Helpers.run_isolated(fn -> apply(module, function, [string, options]) end)

    case isolated do
      {:ok, result} -> result
      {:error, exception} -> {:raised, exception.__struct__, Exception.message(exception)}
    end
  end

  # The same value, struct for struct: a decimal's exponent is part of the
  # value, since `Decimal.to_string/1` shows it. Errors compare whole, so a
  # changed field or message is a difference to look at.
  defp same?(this, that) do
    this == that
  end
end
