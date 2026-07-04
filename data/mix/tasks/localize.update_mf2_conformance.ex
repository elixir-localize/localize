defmodule Mix.Tasks.Localize.UpdateMf2Conformance do
  @shortdoc "Sync the vendored MF2 WG syntax conformance suite from upstream"

  @moduledoc """
  Refreshes the MessageFormat 2 Working Group syntax-conformance test
  files that `Localize.Message.ConformanceTest` consumes.

  Two files are fetched from
  [`unicode-org/message-format-wg`](https://github.com/unicode-org/message-format-wg/tree/main/test/tests)
  and written to `test/support/data/mf2_conformance/`:

    * `syntax.json` — inputs that must parse successfully.
    * `syntax-errors.json` — inputs that must produce syntax errors.

  If the upstream files match what we have on disk, nothing is written
  and the task reports "already in sync". If they differ, the local
  copies are overwritten with the upstream contents and a summary is
  printed showing how many cases each file contains before / after.

  After running the task, run `mix test test/localize/message/conformance_test.exs`
  to confirm the parser still passes every case. Any new conformance
  failure represents either a genuine parser bug or a spec change
  Localize needs to adapt to.

  ## Usage

      # Fetch and update if different.
      mix localize.update_mf2_conformance

      # Do not modify files; exit non-zero if upstream has changed.
      # Intended for CI.
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
    {opts, _rest} = OptionParser.parse!(argv, switches: @switches)
    check? = Keyword.get(opts, :check, false)
    ref = Keyword.get(opts, :ref, @default_ref)

    :ssl.start()
    :inets.start()

    dest_dir = Path.join(File.cwd!(), @vendored_dir)
    File.mkdir_p!(dest_dir)

    Mix.shell().info("MF2 conformance suite ← #{@upstream}@#{ref}")

    results = Enum.map(@files, &fetch_and_compare(&1, dest_dir, ref, check?))

    changed = Enum.filter(results, &match?({:changed, _, _, _}, &1))
    missing = Enum.filter(results, &match?({:missing, _}, &1))

    cond do
      missing != [] ->
        Enum.each(missing, fn {:missing, reason} ->
          Mix.shell().error("  ✗ #{reason}")
        end)

        Mix.raise("update failed")

      changed == [] ->
        Mix.shell().info("  ✓ already in sync")
        :ok

      check? ->
        Enum.each(changed, fn {:changed, name, before_count, after_count} ->
          Mix.shell().error(
            "  ✗ #{name} has drifted (local: #{before_count} tests, upstream: #{after_count})"
          )
        end)

        Mix.raise("""
        The vendored MF2 conformance suite is out of date. Run:

            mix localize.update_mf2_conformance

        to sync, then commit the updated JSON files.
        """)

      true ->
        Enum.each(changed, fn {:changed, name, before_count, after_count} ->
          Mix.shell().info("  ✓ #{name}: #{before_count} → #{after_count} cases")
        end)

        Mix.shell().info("")
        Mix.shell().info("Next: run the conformance tests to check for regressions:")

        Mix.shell().info(
          "    mix test test/localize/message/conformance_test.exs --only mf2_conformance"
        )

        :ok
    end
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

    with {:ok, upstream_body} <- download(url),
         :ok <- validate_json(upstream_body, name) do
      compare_and_write(name, local_path, upstream_body, check?)
    else
      {:error, reason} ->
        {:missing, "#{name}: #{reason}"}
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

    request = {url_charlist, [{~c"accept", ~c"application/json"}]}

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

  defp validate_json(body, name) do
    case :json.decode(body) do
      %{"tests" => tests} when is_list(tests) ->
        :ok

      _ ->
        {:error, "#{name} is not a valid MF2 WG test file (no \"tests\" array)"}
    end
  rescue
    _ -> {:error, "#{name} is not valid JSON"}
  end

  # Best-effort count for diagnostic output. Non-fatal if JSON parsing
  # fails — just returns "?".
  defp test_count(""), do: 0

  defp test_count(body) do
    case :json.decode(body) do
      %{"tests" => tests} when is_list(tests) -> length(tests)
      _ -> "?"
    end
  rescue
    _ -> "?"
  end
end
