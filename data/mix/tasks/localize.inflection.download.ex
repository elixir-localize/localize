defmodule Mix.Tasks.Localize.Inflection.Download do
  @moduledoc """
  Downloads the upstream unicode-org/inflection source data for the
  configured locales into `data/inflection/`.

  Large files (lexicons and inflection pattern XML) are stored in
  the upstream repository with git-lfs and are fetched through the
  GitHub media endpoint at a pinned commit.

      mix localize.inflection.download
      mix localize.inflection.download en es fr

  """

  use Mix.Task

  @shortdoc "Downloads upstream inflection source data"

  # The pinned unicode-org/inflection commit the data is built
  # from. Bump when adopting new upstream data, then regenerate
  # with mix localize.inflection.generate.
  @upstream_sha "2333a964e53a840cd2ce2df419da5306e0cb9dff"
  @media "https://media.githubusercontent.com/media/unicode-org/inflection"
  @raw "https://raw.githubusercontent.com/unicode-org/inflection"
  @resources "inflection/resources/org/unicode/inflection"
  @test_resources "inflection/test/resources/inflection/dialog/inflection"
  @pronoun_test_resources "inflection/test/resources/inflection/dialog/pronoun"
  @default_locales ["en", "es"]

  # Pronoun test suites exist for regional locales whose pronoun
  # tables resolve through the locale fallback chain.
  @pronoun_test_locales ~w(yue_CN zh_CN zh_HK zh_TW)
  @pronoun_extra_tables ~w(zh_Hant)

  @impl true
  def run(argv) do
    locales = if argv == [], do: @default_locales, else: argv

    downloads =
      [
        {:raw, "#{@resources}/features/grammar.xml", "features/grammar.xml"},
        {:raw, "#{@resources}/features/grammar.dtd", "features/grammar.dtd"}
      ] ++
        Enum.flat_map(locales, &locale_downloads/1) ++
        Enum.map(@pronoun_extra_tables, &pronoun_table_download/1) ++
        Enum.map(@pronoun_test_locales, &pronoun_test_download/1)

    Enum.each(downloads, fn {kind, remote, local} ->
      destination = Path.join("data/inflection", local)
      File.mkdir_p!(Path.dirname(destination))

      Mix.shell().info("Fetching #{local}")

      case fetch(kind, remote, destination) do
        :ok ->
          :ok

        :error when kind in [:optional, :optional_media] ->
          File.rm(destination)
          Mix.shell().info("  (not available upstream, skipped)")

        :error ->
          Mix.raise("Download failed: #{remote}")
      end
    end)

    Mix.shell().info("Done. Now run: mix localize.inflection.generate #{Enum.join(locales, " ")}")
  end

  # Large files are git-lfs objects served by the media endpoint;
  # smaller files live in the tree and are served by the raw
  # endpoint (which returns only the lfs pointer for lfs files).
  # Try media first, then raw, rejecting lfs pointer content.
  defp fetch(kind, remote, destination) do
    bases = if kind in [:media, :optional_media], do: [@media, @raw], else: [@raw, @media]

    Enum.reduce_while(bases, :error, fn base, _acc ->
      url = "#{base}/#{@upstream_sha}/#{remote}"

      with 0 <- Mix.shell().cmd("curl -fsSL -o #{destination} #{url}", quiet: true),
           {:ok, file} <- File.open(destination, [:read, :binary]),
           head = IO.binread(file, 40),
           :ok <- File.close(file),
           false <- is_binary(head) and String.starts_with?(head, "version https://git-lfs") do
        {:halt, :ok}
      else
        _other -> {:cont, :error}
      end
    end)
  end

  defp locale_downloads(locale) do
    [
      {:optional_media, "#{@resources}/dictionary/dictionary_#{locale}.lst",
       "dictionary/dictionary_#{locale}.lst"},
      {:optional_media, "#{@resources}/dictionary/inflectional_#{locale}.xml",
       "dictionary/inflectional_#{locale}.xml"},
      {:optional, "#{@resources}/dictionary/supplemental_#{locale}.lst",
       "dictionary/supplemental_#{locale}.lst"},
      {:optional, "#{@resources}/contraction/contractionExpandingTable_#{locale}.csv",
       "contraction/contractionExpandingTable_#{locale}.csv"},
      {:optional, "#{@resources}/exemplar/suffix_#{locale}.csv", "exemplar/suffix_#{locale}.csv"},
      {:optional, "#{@test_resources}/#{locale}.xml", "test/inflection_#{locale}.xml"},
      pronoun_table_download(locale),
      pronoun_test_download(locale)
    ]
  end

  defp pronoun_table_download(locale) do
    {:optional, "#{@resources}/inflection/pronoun_#{locale}.csv", "pronoun/pronoun_#{locale}.csv"}
  end

  defp pronoun_test_download(locale) do
    {:optional, "#{@pronoun_test_resources}/#{locale}.xml", "test/pronoun_#{locale}.xml"}
  end
end
