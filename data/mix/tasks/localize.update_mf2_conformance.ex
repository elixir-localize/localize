defmodule Mix.Tasks.Localize.UpdateMf2Conformance do
  @shortdoc "Sync the vendored MF2 WG conformance suite from upstream"

  @moduledoc """
  Refreshes the MessageFormat 2 Working Group conformance test files
  that `Localize.Message.ConformanceTest` (the parser) and
  `Localize.Message.FormatterConformanceTest` (formatted output)
  consume.

  Every file the suite lists in `@files` is fetched from
  [`unicode-org/message-format-wg`](https://github.com/unicode-org/message-format-wg/tree/main/test/tests)
  and written to `test/support/data/mf2_conformance/`: the syntax,
  data-model error, pattern selection, fallback, bidi and `u:` option
  files, and one file per default function under `functions/`.

  If the upstream files match what we have on disk, nothing is written
  and the task reports "already in sync". If they differ, the local
  copies are overwritten with the upstream contents and a summary is
  printed showing how many cases each file contains before / after.

  The task also lists upstream's `test/tests/` directory and fails,
  naming them, when it holds test files that `@files` does not: a new
  upstream file is otherwise never vendored and never run. Add each to
  `@files` here and to `@files` in
  `Localize.Message.FormatterConformanceTest`, then run the task again.

  After running the task, run the two conformance test files it names
  to confirm every case still passes. Any new conformance failure
  represents either a genuine bug or a spec change Localize needs to
  adapt to.

  ## Usage

      # Fetch and update if different.
      mix localize.update_mf2_conformance

      # Do not modify files; exit non-zero if upstream has changed or
      # has files this task does not list. Intended for CI.
      mix localize.update_mf2_conformance --check

      # Fetch from a specific branch / tag / commit ref instead of main.
      mix localize.update_mf2_conformance --ref v46.0.0
      mix localize.update_mf2_conformance --ref 7a9b3cf

  ## Why this is a data task, not a shipped mix task

  This file lives in `data/mix/tasks/` rather than `lib/mix/tasks/`
  because it is a maintainer utility, not something end users should
  ever need to run. Mix picks it up when `MIX_ENV` includes `data` in
  `elixirc_paths` (currently `:dev` and `:test`) but it is not part
  of the hex package.

  """

  use Mix.Task

  @upstream "unicode-org/message-format-wg"
  @default_ref "main"
  @upstream_tests_dir "test/tests/"
  @files [
    {"syntax.json", "test/tests/syntax.json"},
    {"syntax-errors.json", "test/tests/syntax-errors.json"},
    {"data-model-errors.json", "test/tests/data-model-errors.json"},
    {"pattern-selection.json", "test/tests/pattern-selection.json"},
    {"fallback.json", "test/tests/fallback.json"},
    {"bidi.json", "test/tests/bidi.json"},
    {"u-options.json", "test/tests/u-options.json"},
    {"functions/currency.json", "test/tests/functions/currency.json"},
    {"functions/date.json", "test/tests/functions/date.json"},
    {"functions/datetime.json", "test/tests/functions/datetime.json"},
    {"functions/integer.json", "test/tests/functions/integer.json"},
    {"functions/number.json", "test/tests/functions/number.json"},
    {"functions/offset.json", "test/tests/functions/offset.json"},
    {"functions/percent.json", "test/tests/functions/percent.json"},
    {"functions/string.json", "test/tests/functions/string.json"},
    {"functions/time.json", "test/tests/functions/time.json"}
  ]

  @vendored_dir "test/support/data/mf2_conformance"

  @switches [check: :boolean, ref: :string]

  @impl Mix.Task
  def run(argv) do
    {options, _rest} = OptionParser.parse!(argv, switches: @switches)
    check? = Keyword.get(options, :check, false)
    ref = Keyword.get(options, :ref, @default_ref)

    :ssl.start()
    :inets.start()

    dest_dir = Path.join(File.cwd!(), @vendored_dir)
    File.mkdir_p!(dest_dir)

    Mix.shell().info("MF2 conformance suite ← #{@upstream}@#{ref}")

    results = Enum.map(@files, &fetch_and_compare(&1, dest_dir, ref, check?))

    changed = Enum.filter(results, &match?({:changed, _, _, _}, &1))
    missing = Enum.filter(results, &match?({:missing, _}, &1))

    finish(missing, changed, unlisted_upstream_files(ref), check?)
  end

  # Reports the outcome and raises when the run did not leave the
  # vendored suite equal to upstream's: a file that could not be
  # fetched, a drifted file under --check, or an upstream test file
  # that `@files` does not list.
  defp finish([_ | _] = missing, _changed, _unlisted, _check?) do
    Enum.each(missing, fn {:missing, reason} ->
      Mix.shell().error("  ✗ #{reason}")
    end)

    Mix.raise("update failed")
  end

  defp finish([], [], [], _check?) do
    Mix.shell().info("  ✓ already in sync")
    :ok
  end

  defp finish([], changed, unlisted, check?) do
    Enum.each(changed, &report_changed(&1, check?))
    Enum.each(unlisted, &report_unlisted/1)
    conclude(changed, unlisted, check?)
  end

  defp report_changed({:changed, name, before_count, after_count}, true) do
    Mix.shell().error(
      "  ✗ #{name} has drifted (local: #{before_count} tests, upstream: #{after_count})"
    )
  end

  defp report_changed({:changed, name, before_count, after_count}, false) do
    Mix.shell().info("  ✓ #{name}: #{before_count} → #{after_count} cases")
  end

  defp report_unlisted(upstream_path) do
    Mix.shell().error("  ✗ #{upstream_path} is upstream but not in this task's file list")
  end

  defp conclude(_changed, [_ | _], _check?) do
    Mix.raise("""
    Upstream has MF2 conformance files that are not vendored. Add each to
    @files in this task and to @files in
    test/localize/message/formatter_conformance_test.exs, then run:

        mix localize.update_mf2_conformance
    """)
  end

  defp conclude(_changed, [], true) do
    Mix.raise("""
    The vendored MF2 conformance suite is out of date. Run:

        mix localize.update_mf2_conformance

    to sync, then commit the updated JSON files.
    """)
  end

  defp conclude(_changed, [], false) do
    Mix.shell().info("")
    Mix.shell().info("Next: run the conformance tests to check for regressions:")

    Mix.shell().info(
      "    mix test test/localize/message/conformance_test.exs " <>
        "test/localize/message/formatter_conformance_test.exs"
    )

    :ok
  end

  # The test files upstream holds at `ref` that `@files` does not
  # list. A listing that cannot be read is reported and counts as no
  # unlisted files, so a rate-limited GitHub API does not fail a sync
  # of the files that are listed.
  defp unlisted_upstream_files(ref) do
    url = "https://api.github.com/repos/#{@upstream}/git/trees/#{ref}?recursive=1"

    case upstream_test_paths(url) do
      {:ok, upstream_paths} ->
        listed = Enum.map(@files, fn {_name, upstream_path} -> upstream_path end)
        Enum.sort(upstream_paths -- listed)

      {:error, reason} ->
        Mix.shell().error(
          "  ! upstream's file list was not read (#{reason}); new files not checked"
        )

        []
    end
  end

  defp upstream_test_paths(url) do
    with {:ok, body} <- download(url),
         {:ok, tree} <- decode_tree(body) do
      {:ok, for(%{"path" => path, "type" => "blob"} <- tree, test_file?(path), do: path)}
    end
  end

  # `:json.decode/1` raises on text that is not JSON, so it runs in a
  # process of its own.
  defp decode_tree(body) do
    case Localize.Utils.Helpers.run_isolated(fn -> :json.decode(body) end) do
      {:ok, %{"tree" => tree, "truncated" => false}} when is_list(tree) -> {:ok, tree}
      {:ok, _other} -> {:error, "not a complete tree listing"}
      {:error, _exception} -> {:error, "not valid JSON"}
    end
  end

  defp test_file?(path) do
    String.starts_with?(path, @upstream_tests_dir) and String.ends_with?(path, ".json")
  end

  # Fetch one file, compare against vendored, optionally write.
  #
  # Returns one of:
  #   `{:ok, name}`          — unchanged.
  #   `{:changed, name, n_before, n_after}` — differed (and written, unless --check).
  #   `{:missing, reason}`   — fetch or parse failed; caller raises.
  defp fetch_and_compare({name, upstream_path}, dest_dir, ref, check?) do
    url = "https://raw.githubusercontent.com/#{@upstream}/#{ref}/#{upstream_path}"
    local_path = Path.join(dest_dir, name)

    case checked_upstream(url, name) do
      {:ok, upstream_body} -> compare_and_write(name, local_path, upstream_body, check?)
      {:error, reason} -> {:missing, "#{name}: #{reason}"}
    end
  end

  defp checked_upstream(url, name) do
    with {:ok, upstream_body} <- download(url),
         :ok <- validate_json(upstream_body, name) do
      {:ok, upstream_body}
    end
  end

  # Compares the vendored file against the upstream body and, unless
  # running with --check, writes the upstream body over the local file.
  defp compare_and_write(name, local_path, upstream_body, check?) do
    local_body =
      case File.read(local_path) do
        {:ok, body} -> body
        {:error, _} -> ""
      end

    if local_body == upstream_body do
      {:ok, name}
    else
      unless check? do
        # Names such as "functions/number.json" nest below dest_dir.
        File.mkdir_p!(Path.dirname(local_path))
        File.write!(local_path, upstream_body)
      end

      {:changed, name, test_count(local_body), test_count(upstream_body)}
    end
  end

  defp download(url) do
    url_charlist = String.to_charlist(url)

    # GitHub's API refuses a request with no user agent.
    request = {url_charlist, [{~c"accept", ~c"application/json"}, {~c"user-agent", ~c"mix"}]}

    case :httpc.request(:get, request, [ssl: ssl_options()], []) do
      {:ok, {{_http, status, _reason}, _headers, body}} when status in 200..299 ->
        {:ok, :erlang.list_to_binary(body)}

      {:ok, {{_http, status, reason}, _headers, _body}} ->
        {:error, "HTTP #{status} #{reason}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp ssl_options do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
  end

  # `:json.decode/1` raises on text that is not JSON, so it runs in a
  # process of its own.
  defp validate_json(body, name) do
    case Localize.Utils.Helpers.run_isolated(fn -> :json.decode(body) end) do
      {:ok, %{"tests" => tests}} when is_list(tests) ->
        :ok

      {:ok, _other} ->
        {:error, "#{name} is not a valid MF2 WG test file (no \"tests\" array)"}

      {:error, _exception} ->
        {:error, "#{name} is not valid JSON"}
    end
  end

  # Best-effort count for diagnostic output. Non-fatal if JSON parsing
  # fails — just returns "?".
  defp test_count(""), do: 0

  defp test_count(body) do
    case Localize.Utils.Helpers.run_isolated(fn -> :json.decode(body) end) do
      {:ok, %{"tests" => tests}} when is_list(tests) -> length(tests)
      _not_a_test_file -> "?"
    end
  end
end
