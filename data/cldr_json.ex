defmodule Localize.Data.CldrJson do
  @moduledoc """
  Builds the CLDR JSON that data generation reads, with CLDR's own tools,
  from the CLDR repository in `CLDR_REPO` into `CLDR_PRODUCTION`.

  CLDR publishes its data as XML, and the JSON is what CLDR's
  `Ldml2JsonConverter` makes of it. unicode-org/cldr-json publishes that
  conversion for each release, but runs the converter without
  `fullnumbers`, which keeps a locale's number symbols and formats only for
  the numbering systems the locale uses by default, although CLDR has the
  rest. So the conversion is run here instead, with the options below, from
  the repository at the ref recorded in `priv/localize/cldr_repo_ref`. The
  JSON is generated, never committed.

  A build runs two of CLDR's tools with Maven from the repository's
  `tools/`:

  * `GenerateProductionData` writes the production form of the XML, the
    one CLDR's releases are made from, into a temporary directory.

  * `Ldml2JsonConverter` converts that into the JSON packages, for the
    types generation reads: `main` (the `cldr-*-full` packages),
    `supplemental` (`cldr-core`) and `rbnf` (`cldr-rbnf`).

  Both need Maven, running a JDK at least as recent as the
  `<java-release>` the repository's `tools/pom.xml` declares (21 for CLDR
  49), with read access to the GitHub Packages registry CLDR takes ICU4J
  from.

  The build ends by writing a stamp, `localize_build.txt`, naming the
  repository commit and the options it was built with.
  `Localize.Data.verify_sources/0` accepts the JSON only when the stamp
  matches the repository and these options, so changing an option means
  rebuilding.

  """

  # The converter types generation reads: the per-locale `cldr-*-full`
  # packages, `cldr-core` and `cldr-rbnf`. Each type is converted on its
  # own, as cldr-json's `-t all` also does, one converter per type.
  @types ["main", "supplemental", "rbnf"]

  # CLDR 49's GenerateProductionData drops every locale that is not in ICU
  # and whose coverage is below Basic unless `keepPreBasic` is set: 657
  # locales where CLDR 48 made 766. Not supporting pre-Basic locales is the
  # deliberate position, and CLDR's default already takes it, but the value
  # is stated here so that a changed default cannot move the locale set
  # without a change in this repository.
  @production_options ["--keepPreBasic", "false"]

  # The options cldr-json's `cldr-generate-json.sh` passes, with
  # `fullnumbers` added:
  #
  #   -m .*           every locale
  #   -p true         files grouped into packages (`cldr-numbers-full` …)
  #   -o true         paths no section claims written to an `other` section
  #   -r true         resolved data: each locale carries what it inherits
  #   -s contributed  the lowest draft status kept
  #   -n true         every numbering system's symbols and formats, not
  #                   only Latin digits and the locale's default, native,
  #                   traditional and finance systems
  #
  # `-V`, the version written into the package metadata, is left to its
  # default, CLDR's own version: a major version other than CLDR's makes
  # the converter rewrite the version in the data.
  @converter_options [
    "-m",
    ".*",
    "-p",
    "true",
    "-o",
    "true",
    "-r",
    "true",
    "-s",
    "contributed",
    "-n",
    "true"
  ]

  # The heap cldr-json's driver gives Maven. The conversion runs a thread
  # per core and needs more with more of them: on 16 threads it peaked at
  # 17 GB resident under this heap and thrashed under 8 GB. `MAVEN_OPTS`
  # can set another heap.
  @maven_options "-Xmx16384m -Dexec.cleanupDaemonThreads=false"

  @production_data_class "org.unicode.cldr.tool.GenerateProductionData"
  @converter_class "org.unicode.cldr.json.Ldml2JsonConverter"

  @stamp_file "localize_build.txt"

  @doc """
  Builds the CLDR JSON from a CLDR repository checkout.

  The output directory is cleared first, so that a package or locale
  dropped upstream cannot survive from an earlier build. A directory is
  cleared only when it is empty or holds CLDR JSON already (a stamp or a
  `cldr-*` package); anything else stops the build.

  ### Arguments

  * `repository` is the path to a checkout of the CLDR repository, with
    no uncommitted changes to tracked files.

  * `output` is the directory to write the JSON into.

  ### Returns

  * `{:ok, stamp}` with the stamp the build wrote, as `stamp/1` returns it.

  * `{:error, message}` when the build could not start or a step failed.

  """
  @spec build(String.t(), String.t()) :: {:ok, %{String.t() => String.t()}} | {:error, String.t()}
  def build(repository, output) do
    with :ok <- check_maven(),
         :ok <- check_java(repository),
         {:ok, commit} <- clean_commit(repository),
         :ok <- clear(output) do
      staging =
        Path.join(
          System.tmp_dir!(),
          "localize_cldr_production_#{System.unique_integer([:positive])}"
        )

      result = build_into(repository, staging, output, commit)
      _removed = File.rm_rf(staging)
      result
    end
  end

  @doc """
  Returns the stamp of the JSON in a directory.

  ### Arguments

  * `directory` is the directory the JSON was built into.

  ### Returns

  * A map of the stamp's fields: `"commit"`, the repository commit it was
    built from; `"describe"`, that commit as `git describe` names it from
    CLDR's release tags; and `"types"`, `"production_data"` and
    `"converter"`, the options.

  * `nil` when the directory holds no stamp — no build, a build that did
    not finish, or JSON from elsewhere.

  """
  @spec stamp(String.t()) :: %{String.t() => String.t()} | nil
  def stamp(directory) do
    case File.read(Path.join(directory, @stamp_file)) do
      {:ok, contents} -> parse_stamp(contents)
      {:error, _absent} -> nil
    end
  end

  @doc """
  Returns whether a stamp records the options a build uses now.

  ### Arguments

  * `stamp` is a stamp as `stamp/1` returns it.

  ### Returns

  * `true` when the stamp's options are the current ones.

  * `false` otherwise.

  """
  @spec current_options?(%{String.t() => String.t()}) :: boolean()
  def current_options?(stamp) when is_map(stamp) do
    Map.take(stamp, Map.keys(options())) == options()
  end

  defp options do
    %{
      "types" => Enum.join(@types, " "),
      "production_data" => Enum.join(@production_options, " "),
      "converter" => Enum.join(@converter_options, " ")
    }
  end

  # ── Steps ──────────────────────────────────────────────────────

  defp build_into(repository, staging, output, commit) do
    common = Path.join(staging, "common")

    # The converter reads a `seed` directory beside `common` and fails
    # without one, as cldr-json's driver notes; production data has none.
    seed_directories = [
      Path.join([staging, "seed", "main"]),
      Path.join([staging, "seed", "annotations"])
    ]

    with :ok <- maven(repository, ["compile"]),
         :ok <-
           maven(
             repository,
             exec(@production_data_class, repository, ["-d", common | @production_options])
           ),
         :ok <- make_directories(seed_directories),
         :ok <- convert(repository, staging, output) do
      write_stamp(repository, output, commit)
    end
  end

  defp convert(repository, staging, output) do
    Enum.reduce_while(@types, :ok, fn type, :ok ->
      arguments = @converter_options ++ ["-t", type, "-d", output]

      case maven(repository, exec(@converter_class, staging, arguments)) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  # `exec:java` runs a class from the module's classpath. `CLDR_DIR` is the
  # CLDR tree the class reads: the repository for GenerateProductionData,
  # the production data for the converter. The plugin splits `exec.args` on
  # whitespace outside double quotes.
  defp exec(class, cldr_directory, arguments) do
    [
      "exec:java",
      "-Dexec.mainClass=#{class}",
      "-DCLDR_DIR=#{cldr_directory}",
      "-Dexec.args=#{Enum.map_join(arguments, " ", &quote_argument/1)}"
    ]
  end

  defp quote_argument(argument) do
    if String.match?(argument, ~r/\s/), do: ~s("#{argument}"), else: argument
  end

  defp maven(repository, arguments) do
    arguments = [
      "-B",
      "-q",
      "--file=#{Path.join([repository, "tools", "pom.xml"])}",
      "-pl",
      "cldr-code" | arguments
    ]

    # The JVM takes the last of repeated options, so `MAVEN_OPTS` from the
    # environment follows ours and can override the heap.
    maven_options = String.trim("#{@maven_options} #{System.get_env("MAVEN_OPTS")}")

    Mix.shell().info("mvn #{Enum.join(arguments, " ")}")

    case System.cmd("mvn", arguments,
           env: [{"MAVEN_OPTS", maven_options}],
           into: IO.binstream(:stdio, :line),
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        :ok

      {_output, status} ->
        {:error, "mvn exited with status #{status}, running #{Enum.join(arguments, " ")}"}
    end
  end

  defp make_directories(directories) do
    Enum.reduce_while(directories, :ok, fn directory, :ok ->
      case File.mkdir_p(directory) do
        :ok ->
          {:cont, :ok}

        {:error, reason} ->
          {:halt, {:error, "Cannot create #{directory}: #{:file.format_error(reason)}"}}
      end
    end)
  end

  # ── Preconditions ──────────────────────────────────────────────

  defp check_maven do
    if System.find_executable("mvn") do
      :ok
    else
      {:error, "Maven (`mvn`) is needed to build the CLDR JSON and is not on the PATH."}
    end
  end

  # CLDR's tools declare the JDK release they are compiled for, and it
  # moves between CLDR versions: 49 requires 21 where 48 did not. Maven
  # would otherwise fail minutes in with "invalid target release", which
  # reads as a Maven problem rather than a JDK one. The JDK checked is the
  # one Maven runs, which `JAVA_HOME` selects and `java` on the PATH may not
  # be.
  defp check_java(repository) do
    with {:ok, required} <- required_java(repository),
         {:ok, running} <- maven_java() do
      if running >= required do
        :ok
      else
        {:error,
         """
         CLDR's tools at #{repository} need JDK #{required} or later, and Maven runs JDK #{running}.
         Point JAVA_HOME at JDK #{required}, for example:

             JAVA_HOME=$(/usr/libexec/java_home -v #{required}) mix localize.build_cldr_json
         """}
      end
    end
  end

  defp required_java(repository) do
    path = Path.join([repository, "tools", "pom.xml"])

    with {:ok, pom} <- File.read(path),
         [_match, release] <- Regex.run(~r{<java-release>(\d+)</java-release>}, pom) do
      {:ok, String.to_integer(release)}
    else
      _unreadable -> {:error, "Cannot read the <java-release> CLDR's tools need from #{path}."}
    end
  end

  defp maven_java do
    case System.cmd("mvn", ["-v"], stderr_to_stdout: true) do
      {output, 0} ->
        case Regex.run(~r/Java version: (?:1\.)?(\d+)/, output) do
          [_match, release] -> {:ok, String.to_integer(release)}
          nil -> {:error, "Cannot read the JDK version from `mvn -v`:\n#{output}"}
        end

      {output, status} ->
        {:error, "`mvn -v` exited with status #{status}:\n#{output}"}
    end
  end

  # The stamp records a commit, so the build refuses a checkout whose
  # tracked files differ from it. Untracked files, such as Maven's `target`
  # directories, are not data.
  defp clean_commit(repository) do
    with {:ok, changes} <- git(repository, ["status", "--porcelain", "--untracked-files=no"]),
         {:clean, ""} <- {:clean, String.trim(changes)},
         {:ok, commit} <- git(repository, ["rev-parse", "HEAD"]) do
      {:ok, String.trim(commit)}
    else
      {:clean, _changes} ->
        {:error,
         "#{repository} has uncommitted changes, so the JSON would not be the data of any commit."}

      :error ->
        {:error, "#{repository} is not a readable git checkout of the CLDR repository."}
    end
  end

  # A mistyped CLDR_PRODUCTION must not cost anyone a directory, so only
  # one that holds nothing, or CLDR JSON, is cleared.
  defp clear(output) do
    case File.ls(output) do
      {:ok, entries} ->
        clear(output, entries)

      {:error, :enoent} ->
        make_directories([output])

      {:error, reason} ->
        {:error, "Cannot read #{output}: #{:file.format_error(reason)}"}
    end
  end

  defp clear(_output, []), do: :ok

  defp clear(output, entries) do
    if Enum.any?(entries, &(&1 == @stamp_file or String.starts_with?(&1, "cldr-"))) do
      Mix.shell().info("Clearing #{output}")
      remove_entries(output, entries)
    else
      {:error,
       """
       #{output} holds files that are not CLDR JSON, so it is not cleared for the build.
       Point CLDR_PRODUCTION at an empty directory, or at one holding CLDR JSON.
       """}
    end
  end

  defp remove_entries(output, entries) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      case File.rm_rf(Path.join(output, entry)) do
        {:ok, _removed} ->
          {:cont, :ok}

        {:error, reason, file} ->
          {:halt, {:error, "Cannot remove #{file}: #{:file.format_error(reason)}"}}
      end
    end)
  end

  # ── The stamp ──────────────────────────────────────────────────

  # One `field value` line per field, written last so that only a build
  # that finished carries one.
  defp write_stamp(repository, output, commit) do
    describe =
      case git(repository, ["describe", "--tags", "--always", "--match", "release-*"]) do
        {:ok, description} -> String.trim(description)
        :error -> commit
      end

    stamp = Map.merge(options(), %{"commit" => commit, "describe" => describe})
    contents = Enum.map_join(Enum.sort(stamp), "", fn {field, value} -> "#{field} #{value}\n" end)

    case File.write(Path.join(output, @stamp_file), contents) do
      :ok ->
        {:ok, stamp}

      {:error, reason} ->
        {:error, "Cannot write the build stamp into #{output}: #{:file.format_error(reason)}"}
    end
  end

  defp parse_stamp(contents) do
    for line <- String.split(contents, "\n", trim: true),
        [field, value] <- [String.split(line, " ", parts: 2)],
        into: %{},
        do: {field, value}
  end

  defp git(directory, arguments) do
    case System.cmd("git", arguments, cd: directory, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {_output, _status} -> :error
    end
  end
end
