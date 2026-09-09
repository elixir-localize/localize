defmodule Mix.Tasks.Localize.Inflection.Generate do
  @moduledoc """
  Compiles downloaded upstream source data into per-locale runtime
  artifacts under `priv/localize/inflection/`.

  With no arguments it generates every locale the inflection data
  supports — the complete set the packaged hash manifest and the CDN
  publish expect. Pass locales
  explicitly only to scope a partial regeneration while iterating.

      mix localize.inflection.generate          # all supported locales
      mix localize.inflection.generate en es    # just these

  Run `mix localize.inflection.download` first.

  """

  use Mix.Task

  alias Localize.Inflection.Locale

  @shortdoc "Generates per-locale inflection data artifacts"

  @impl true
  def run(argv) do
    locales = if argv == [], do: Locale.supported(), else: argv

    # Each locale reads only its own dictionary and paradigm files and
    # writes only its own artifact, so the work is independent. It is
    # also CPU-bound — a single locale saturates one scheduler for
    # minutes — so one task per scheduler turns a sum into a maximum.
    # `timeout: :infinity` because the default 5s is far below the time
    # a large locale takes, and messages are returned rather than
    # printed inside the task so concurrent output cannot interleave.
    locales
    |> Task.async_stream(&{&1, generate_locale(&1, features())},
      max_concurrency: System.schedulers_online(),
      timeout: :infinity,
      ordered: false
    )
    |> Enum.each(fn
      {:ok, {_locale, message}} ->
        Mix.shell().info(message)

      # A locale that dies takes its artifact with it but must not
      # take the run with it, and must say which locale it was:
      # `ar`'s dictionary is an order of magnitude larger than the
      # rest and is the one that will exhaust memory first.
      {:exit, reason} ->
        Mix.shell().error("A locale failed to generate: #{inspect(reason)}")
    end)

    copy_script_pronoun_tables()
  end

  # Parsed once and passed to every task; parsing it per locale was
  # repeating the same work 47 times.
  defp features do
    Localize.Inflection.DataGen.Features.parse_file("data/inflection/features/grammar.xml")
  end

  # A features-only language has a grammar.xml section but no
  # dictionary (yue).
  defp generate_locale(locale, features) do
    if File.exists?("data/inflection/dictionary/dictionary_#{locale}.lst") or
         Map.has_key?(features, locale) do
      generate(locale)
    else
      "Skipping #{locale}: no dictionary_#{locale}.lst downloaded"
    end
  end

  # Supported locales carry their pronoun table folded into
  # `<locale>.etf`. The only standalone CSVs kept are the script-only
  # fixtures that no shipped locale owns (e.g. zh_Hant), which the
  # conformance tests reach through the fallback chain; they are not
  # uploaded to the CDN (only `*.etf` is).
  defp copy_script_pronoun_tables do
    File.mkdir_p!("priv/localize/inflection")
    supported = MapSet.new(Locale.supported())

    "data/inflection/pronoun/pronoun_*.csv"
    |> Path.wildcard()
    |> Enum.reject(fn path ->
      locale = path |> Path.basename(".csv") |> String.replace_prefix("pronoun_", "")
      MapSet.member?(supported, locale)
    end)
    |> Enum.each(fn path ->
      File.cp!(path, Path.join("priv/localize/inflection", Path.basename(path)))
    end)
  end

  defp generate(locale) do
    artifact = Localize.Inflection.DataGen.Generate.generate(locale)

    "Generated #{locale}: " <>
      "#{Localize.Inflection.Lexicon.size(artifact.lexicon)} lexicon entries, " <>
      "#{tuple_size(artifact.patterns)} patterns, " <>
      "#{tuple_size(artifact.grammeme_names)} grammemes"
  end
end
