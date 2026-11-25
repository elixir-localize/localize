defmodule Mix.Tasks.Localize.Gettext.Mf2 do
  @shortdoc "Converts Gettext catalogs and gettext calls from %{name} to MF2"

  @moduledoc """
  Converts an application's Gettext catalogs and the msgids of its `gettext` calls from Gettext's `%{name}` syntax to MF2, for a backend that uses `Localize.Gettext.Interpolation`.

  Every `.pot` and `.po` file under the catalog directories is converted with `Localize.Gettext.Migration.convert/2`, and every `.ex`, `.exs` and `.heex` file under the source directories with `Localize.Gettext.Migration.convert_source/2`. Both apply the same conversion to a msgid, so a call and its catalog entry still match, and each converted message formats as the original did. Only the files that change are written; a catalog is written as `Expo.PO.compose/1` writes it.

  ### What is converted

  A msgid is the key a translation is found by, so an entry is converted only where every lookup of it changes with it, and is otherwise left as it is, which the interpolator still reads:

  * A call whose domain is an expression may look up any msgid of any domain, so no entry is converted, and the call is reported.

  * A domain with a call whose msgid is an expression, as in a `translate_error/1` that translates Ecto's and Ash's messages in `errors`, keeps all its entries, and the call is reported. Where such a lookup only ever receives msgids written in calls in the converted source, as a `Gettext.gettext(MyApp.Gettext, label)` whose labels come from `gettext_noop("…")` does, name the domain with `--trust` to convert it. Never trust `errors`, whose msgids come from Ecto and Ash at runtime.

  * Otherwise an entry is converted when every source file its `#:` references name lies under a `--source` directory, or, with no references, when a call there uses it. A catalog shared with another application, whose references name `../other_app/lib/page.ex`, keeps that application's entries unless its source is given too.

  References are read relative to `--root`, the directory the catalogs were extracted in.

  With `--plurals`, each plural entry that every catalog of its domain can write as one `.match` message, as `Localize.Gettext.Migration.convertible_plurals/2` tells, becomes a singular entry, and its `ngettext` calls become `gettext` calls with the count in their bindings. A catalog's language is its `Language` header, or else the directory above its `LC_MESSAGES`. A domain is a catalog's file name, and a call's domain its literal domain argument, or `--default-domain` for a call that names none. Run `mix format` afterwards.

  Run it on a clean working tree, so the changes can be reviewed as a diff. A msgid the task cannot rewrite, one written as a sigil, a concatenation or an expression, is listed with its file and line for a person to convert.

  ### Usage

      mix localize.gettext.mf2 [--priv DIR]... [--source DIR]... [--root DIR] [--trust DOMAIN]... [--plurals] [--dry-run]

  ### Options

  * `--priv` is a directory of catalogs, which may be given more than once. The default is `priv/gettext`.

  * `--source` is a directory of source files, which may be given more than once. The default is `lib`.

  * `--root` is the directory catalog references are relative to. The default is the current directory.

  * `--trust` is a domain whose dynamic lookups receive only msgids written in calls in the converted source, which may be given more than once.

  * `--plurals` converts plural entries and calls to `.match` messages.

  * `--source-locale` is the language msgids are written in, for the plural rules of a converted msgid. The default is `en`.

  * `--default-domain` is the domain of a call that names none. The default is `default`.

  * `--dry-run` reports what would change without writing any file.

  """

  use Mix.Task

  alias Localize.Gettext.Migration
  alias Localize.Gettext.Migration.Selection

  @switches [
    priv: :keep,
    source: :keep,
    dry_run: :boolean,
    plurals: :boolean,
    source_locale: :string,
    default_domain: :string,
    root: :string,
    trust: :keep
  ]
  @catalog_pattern "**/*.{pot,po}"
  @source_pattern "**/*.{ex,exs,heex}"

  @impl Mix.Task
  def run(arguments) do
    {options, _rest, invalid} = OptionParser.parse(arguments, strict: @switches)
    refuse_invalid(invalid)
    Mix.Task.run("app.config")

    dry_run? = Keyword.get(options, :dry_run, false)
    source_directories = directories(Keyword.get_values(options, :source), ["lib"])
    catalogs = files(Keyword.get_values(options, :priv), ["priv/gettext"], @catalog_pattern)
    sources = files(source_directories, [], @source_pattern)

    source_locale = Keyword.get(options, :source_locale, "en")
    default_domain = Keyword.get(options, :default_domain, "default")
    parsed = Enum.map(catalogs, &parse_catalog/1)
    texts = Enum.map(sources, &{&1, File.read!(&1)})

    selection =
      Selection.select(
        Enum.filter(parsed, &match?({_path, _catalog, _locale}, &1)),
        lookups(texts, default_domain),
        source_directories,
        Keyword.get(options, :root, "."),
        Keyword.get_values(options, :trust)
      )

    plurals =
      agreed_plurals(parsed, Keyword.get(options, :plurals, false), source_locale, selection.only)

    conversion = [
      plurals: plurals,
      only: selection.only,
      source_locale: source_locale,
      default_domain: default_domain
    ]

    catalog_counts = Enum.map(parsed, &convert_catalog(&1, conversion, dry_run?))
    source_reports = Enum.map(texts, &convert_source(&1, conversion, dry_run?))

    report(catalog_counts, source_reports, selection.notes, dry_run?)
  end

  defp directories([], defaults) do
    defaults
  end

  defp directories(directories, _defaults) do
    directories
  end

  defp lookups(texts, default_domain) do
    for {path, text} <- texts,
        {:ok, lookups} <- [Migration.lookups(text, default_domain: default_domain)],
        lookup <- lookups,
        do: {path, lookup}
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

  defp parse_catalog(path) do
    case Expo.PO.parse_file(path) do
      {:ok, catalog} -> {path, catalog, catalog_locale(path, catalog)}
      {:error, exception} -> {:error, exception}
    end
  end

  # A translation's language from its header, or else from the directory
  # above its `LC_MESSAGES`; a template has none.
  defp catalog_locale(path, catalog) do
    language = header_value(catalog, "Language")

    if language == "" do
      directory_locale(Path.split(path))
    else
      language
    end
  end

  defp header_value(catalog, name) do
    catalog
    |> Expo.Messages.get_header(name)
    |> Enum.join()
    |> String.trim()
  end

  defp directory_locale(segments) do
    case Enum.find_index(segments, &(&1 == "LC_MESSAGES")) do
      nil -> nil
      0 -> nil
      index -> Enum.at(segments, index - 1)
    end
  end

  # The plural entries to convert in each domain: those every catalog of
  # the domain can convert, so a template, its translations and the calls
  # convert the same ones.
  defp agreed_plurals(_parsed, false, _source_locale, _only) do
    false
  end

  defp agreed_plurals(parsed, true, source_locale, only) do
    parsed
    |> Enum.filter(&match?({_path, _catalog, _locale}, &1))
    |> Enum.group_by(fn {path, _catalog, _locale} -> domain(path) end)
    |> Map.new(fn {domain, catalogs} ->
      selected = Map.get(only, domain, MapSet.new())
      agreed = agreed_in_domain(catalogs, source_locale)

      {domain,
       MapSet.filter(agreed, fn {msgctxt, msgid, _plural} ->
         MapSet.member?(selected, {msgctxt, msgid})
       end)}
    end)
  end

  defp agreed_in_domain(catalogs, source_locale) do
    catalogs
    |> Enum.map(&convertible(&1, source_locale))
    |> Enum.reduce(&MapSet.intersection/2)
  end

  defp convertible({path, catalog, locale}, source_locale) do
    case Migration.convertible_plurals(catalog, locale: locale, source_locale: source_locale) do
      {:ok, keys} -> keys
      {:error, exception} -> Mix.raise("#{path}: #{Exception.message(exception)}")
    end
  end

  defp domain(path) do
    Selection.domain(path)
  end

  defp convert_catalog({:error, exception}, _conversion, _dry_run?) do
    {:error, exception}
  end

  defp convert_catalog({path, catalog, locale}, conversion, dry_run?) do
    options = [
      plurals: domain_plurals(conversion[:plurals], domain(path)),
      only: Map.get(conversion[:only], domain(path), MapSet.new()),
      locale: locale,
      source_locale: conversion[:source_locale]
    ]

    case Migration.convert(catalog, options) do
      {:ok, converted, renames} ->
        write_catalog(path, catalog, converted, dry_run?)
        {path, converted != catalog, length(renames)}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp domain_plurals(false, _domain) do
    false
  end

  defp domain_plurals(by_domain, domain) do
    Map.get(by_domain, domain, MapSet.new())
  end

  defp write_catalog(path, catalog, converted, dry_run?) do
    if converted != catalog and not dry_run? do
      File.write!(path, Expo.PO.compose(converted))
    end
  end

  defp convert_source({path, source}, conversion, dry_run?) do
    case Migration.convert_source(source, conversion) do
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

  defp report(catalog_counts, source_reports, notes, dry_run?) do
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

    Enum.each(notes, &shell.info(note(&1)))
    :ok
  end

  defp note({:dynamic_domain, path, line}) do
    "#{path}:#{line}: the domain of this call is an expression, so it may look up any entry " <>
      "and no catalog entry is converted."
  end

  defp note({:dynamic_lookup, domain, path, line}) do
    "#{path}:#{line}: the msgid of this call in #{domain} is an expression, so it may look up " <>
      "any of the domain's entries and none is converted." <> trust_hint(domain)
  end

  defp note({:outside, domain, count}) do
    "#{count} entries of #{domain} are used by source outside the --source directories and are " <>
      "not converted; give that source with --source to convert them."
  end

  # The msgids `errors` translates come from Ecto and Ash at runtime, so
  # trusting it would lose their translations.
  defp trust_hint("errors") do
    ""
  end

  defp trust_hint(domain) do
    " If it only receives msgids written in calls such as gettext_noop, convert the domain " <>
      "with --trust #{domain}."
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
