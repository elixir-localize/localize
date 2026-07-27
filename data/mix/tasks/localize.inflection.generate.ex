defmodule Mix.Tasks.Localize.Inflection.Generate do
  @moduledoc """
  Compiles downloaded upstream source data into per-locale runtime
  artifacts under `priv/localize/inflection/`.

  With no arguments it generates every locale in
  `Localize.Inflection.Locale.supported/0` — the complete set the
  packaged hash manifest and the CDN publish expect. Pass locales
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

    Enum.each(locales, fn locale ->
      if File.exists?("data/inflection/dictionary/dictionary_#{locale}.lst") or
           features_only?(locale) do
        generate(locale)
      else
        Mix.shell().info("Skipping #{locale}: no dictionary_#{locale}.lst downloaded")
      end
    end)

    copy_script_pronoun_tables()
  end

  # A features-only language has a grammar.xml section but no
  # dictionary (yue).
  defp features_only?(locale) do
    features =
      Localize.Inflection.DataGen.Features.parse_file("data/inflection/features/grammar.xml")

    Map.has_key?(features, locale)
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
    Mix.shell().info("Generating #{locale}")
    artifact = Localize.Inflection.DataGen.Generate.generate(locale)

    Mix.shell().info(
      "  #{Localize.Inflection.Lexicon.size(artifact.lexicon)} lexicon entries, " <>
        "#{tuple_size(artifact.patterns)} patterns, " <>
        "#{tuple_size(artifact.grammeme_names)} grammemes"
    )
  end
end
