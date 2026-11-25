defmodule Mix.Tasks.Localize.Gettext.Mf2 do
  @shortdoc "Converts Gettext catalogs and gettext calls from %{name} to MF2"

  @moduledoc """
  Converts an application's Gettext catalogs and the msgids of its `gettext` calls from Gettext's `%{name}` syntax to MF2, for a backend that uses `Localize.Gettext.Interpolation`.

  Every `.pot` and `.po` file under the catalog directories is converted with `Localize.Gettext.Migration.convert/1`, and every `.ex`, `.exs` and `.heex` file under the source directories with `Localize.Gettext.Migration.convert_source/1`. Both apply the same conversion to a msgid, so a call and its catalog entry still match, and each converted message formats as the original did. Only the files that change are written; a catalog is written as `Expo.PO.compose/1` writes it.

  A catalog is shared by every application or package whose source its msgids come from, as the `#:` references of its entries show, such as `../my_other_app/lib/page.ex:12`. Convert all of their source in the same run, with a `--source` for each, or the calls in the source left out keep the old msgids and lose their translations.

  Run it on a clean working tree, so the changes can be reviewed as a diff. A msgid the task cannot rewrite, one written as a sigil, a concatenation or an expression, is listed with its file and line for a person to convert.

  ### Usage

      mix localize.gettext.mf2 [--priv DIR]... [--source DIR]... [--dry-run]

  ### Options

  * `--priv` is a directory of catalogs, which may be given more than once. The default is `priv/gettext`.

  * `--source` is a directory of source files, which may be given more than once. The default is `lib`.

  * `--dry-run` reports what would change without writing any file.

  """

  use Mix.Task

  alias Localize.Gettext.Migration

  @switches [priv: :keep, source: :keep, dry_run: :boolean]
  @catalog_pattern "**/*.{pot,po}"
  @source_pattern "**/*.{ex,exs,heex}"

  @impl Mix.Task
  def run(arguments) do
    {options, _rest, invalid} = OptionParser.parse(arguments, strict: @switches)
    refuse_invalid(invalid)
    Mix.Task.run("app.config")

    dry_run? = Keyword.get(options, :dry_run, false)
    catalogs = files(Keyword.get_values(options, :priv), ["priv/gettext"], @catalog_pattern)
    sources = files(Keyword.get_values(options, :source), ["lib"], @source_pattern)

    catalog_counts = Enum.map(catalogs, &convert_catalog(&1, dry_run?))
    source_reports = Enum.map(sources, &convert_source(&1, dry_run?))

    report(catalog_counts, source_reports, dry_run?)
  end

  defp refuse_invalid([]) do
    :ok
  end

  defp refuse_invalid([_ | _] = invalid) do
    Mix.raise("mix localize.gettext.mf2: unknown option #{inspect(invalid)}")
  end

  defp files([], defaults, pattern) do
    files(defaults, [], pattern)
  end

  defp files(directories, _defaults, pattern) do
    directories
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, pattern)))
    |> Enum.sort()
  end

  defp convert_catalog(path, dry_run?) do
    with {:ok, catalog} <- Expo.PO.parse_file(path),
         {:ok, converted, renames} <- Migration.convert(catalog) do
      if converted != catalog and not dry_run? do
        File.write!(path, Expo.PO.compose(converted))
      end

      {path, converted != catalog, length(renames)}
    end
  end

  defp convert_source(path, dry_run?) do
    source = File.read!(path)

    case Migration.convert_source(source) do
      {:ok, converted, report} ->
        write_changed(path, source, converted, dry_run?)
        {path, report}

      {:error, exception} ->
        Mix.raise("#{path}: #{Exception.message(exception)}")
    end
  end

  defp write_changed(path, source, converted, dry_run?) do
    if converted != source and not dry_run? do
      File.write!(path, converted)
    end
  end

  defp report(catalog_counts, source_reports, dry_run?) do
    shell = Mix.shell()
    verb = verb(dry_run?)

    {catalogs_changed, renames, catalog_errors} = summarize_catalogs(catalog_counts)
    sources_changed = Enum.count(source_reports, fn {_path, report} -> report.rewritten > 0 end)
    rewritten = Enum.sum_by(source_reports, fn {_path, report} -> report.rewritten end)

    shell.info(
      "Catalogs: #{catalogs_changed} of #{length(catalog_counts)} #{verb}, #{renames} msgids renamed."
    )

    shell.info(
      "Source: #{sources_changed} of #{length(source_reports)} files #{verb}, #{rewritten} msgids rewritten."
    )

    Enum.each(catalog_errors, fn {path, exception} ->
      shell.error("#{path}: not converted, #{Exception.message(exception)}")
    end)

    for {path, report} <- source_reports, skipped <- report.skipped do
      shell.info("#{path}:#{skipped.line}: #{skipped.call}: #{skipped.reason}")
    end

    :ok
  end

  defp verb(true) do
    "would change"
  end

  defp verb(false) do
    "changed"
  end

  defp summarize_catalogs(catalog_counts) do
    Enum.reduce(catalog_counts, {0, 0, []}, fn
      {_path, changed?, renames}, {changed, total, errors} ->
        {changed + count(changed?), total + renames, errors}

      {:error, exception}, {changed, total, errors} ->
        {changed, total, [{exception_path(exception), exception} | errors]}
    end)
  end

  defp count(true) do
    1
  end

  defp count(false) do
    0
  end

  defp exception_path(%{file: file}) when is_binary(file) do
    file
  end

  defp exception_path(_exception) do
    "a catalog"
  end
end
