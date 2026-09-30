defmodule Mix.Tasks.Localize.PublishLocales do
  @shortdoc "Publishes the generated locale data to the CDN"

  @moduledoc """
  Publishes the generated locale ETF files to Cloudflare R2, the store the
  locale CDN serves, under the current data version.

  The locales are generated from the CLDR JSON that
  `mix localize.build_cldr_json` builds with CLDR's own converter, which
  needs more memory than a CI runner has, so the data is generated and
  published from a maintainer's machine. CI only checks that R2 holds the
  data the committed hash manifest pins.

  The task checks that the CLDR sources are the recorded ones and that
  every locale file matches `priv/localize/locale_hashes.etf`, then:

  1. uploads each locale file to `locales/<data version>/<locale>.etf`,
     skipping any R2 already holds with the same content, so that a
     publish stopped part way is resumed rather than repeated; a request R2
     answers with a transient error is retried;

  2. purges those URLs from the Cloudflare cache, so that no copy of a
     replaced file is served against the new manifest;

  3. records the manifest at `locales/<data version>/manifest/locale_hashes`,
     which is what CI compares with the committed one.

  Nothing is done when R2 already records the same manifest. A data
  version the latest release tag carries is never replaced: changing
  released data needs `mix localize.bump_patch_version` first.

  ## Usage

      mix localize.generate_locales
      mix localize.publish_locales --dry-run
      mix localize.publish_locales

  ## Options

  * `--dry-run` — make every check and report what would be published,
    without contacting R2 or Cloudflare.

  * `--skip-purge` — publish without purging the Cloudflare cache, which
    then serves cached copies of replaced files for up to an hour.

  ## Environment

  * `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID` and `R2_SECRET_ACCESS_KEY` — the
    R2 credentials.

  * `R2_BUCKET` — the bucket, `content` by default.

  * `ELIXIR_LOCALIZE_CACHE_PURGE_API_TOKEN` and `CLOUDFLARE_ZONE_ID` — a
    Cloudflare API token with the Cache Purge permission on the zone, and
    the zone's ID, for the cache purge.

  """

  use Mix.Task

  alias Localize.Data.R2

  @default_bucket "content"
  @prefix "locales"
  @manifest_record "manifest/locale_hashes"
  @manifest_file "priv/localize/locale_hashes.etf"
  @upload_concurrency 8
  @progress_every 50
  @purge_batch_size 30

  @impl Mix.Task
  def run(args) do
    {options, _rest} =
      OptionParser.parse!(args, strict: [dry_run: :boolean, skip_purge: :boolean])

    Mix.Task.run("app.config")
    {:ok, _started} = Application.ensure_all_started([:localize, :inets, :ssl])

    version = Localize.Locale.Provider.version_segment()
    bucket = System.get_env("R2_BUCKET") || @default_bucket

    with :ok <- Localize.Data.verify_sources(),
         {:ok, manifest} <- read_manifest(),
         {:ok, files} <- generated_files(manifest),
         :ok <- check_unreleased(version) do
      plan = %{version: version, bucket: bucket, manifest: manifest, files: files}

      if options[:dry_run] do
        report(plan, options)
      else
        publish(plan, options)
      end
    else
      {:error, message} -> Mix.raise(message)
    end
  end

  # ── Checks ─────────────────────────────────────────────────────

  defp read_manifest do
    path = Path.join(File.cwd!(), @manifest_file)

    case File.read(path) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, reason} -> {:error, "Cannot read #{path}: #{:file.format_error(reason)}"}
    end
  end

  # Every locale the manifest names, with the generated file that must hash
  # to it: the files were generated from the recorded sources, and the
  # manifest is the one to be committed with them.
  defp generated_files(manifest_bytes) do
    directory = Localize.Data.locales_output_dir()
    hashes = :erlang.binary_to_term(manifest_bytes, [:safe])

    {files, mismatched} =
      hashes
      |> Enum.map(fn {locale, hash} -> matching_file(directory, "#{locale}.etf", hash) end)
      |> Enum.split_with(&match?({:ok, _file}, &1))

    files = for {:ok, file} <- files, do: file

    case for({:mismatch, name} <- mismatched, do: name) do
      [] ->
        {:ok, Enum.sort(files)}

      names ->
        {:error,
         """
         #{length(names)} locale files in #{directory} do not match #{@manifest_file}, \
         such as #{names |> Enum.sort() |> Enum.take(5) |> Enum.join(", ")}.
         Run `mix localize.generate_locales` to generate every locale and its manifest.
         """}
    end
  end

  defp matching_file(directory, name, hash) do
    path = Path.join(directory, name)

    case File.read(path) do
      {:ok, bytes} ->
        if :crypto.hash(:sha256, bytes) == hash, do: {:ok, {name, path}}, else: {:mismatch, name}

      {:error, _absent} ->
        {:mismatch, name}
    end
  end

  # Data versions only move forward, so the current data version is
  # released exactly when the latest release tag carries it. The tags read
  # are the local ones.
  defp check_unreleased(version) do
    with {:ok, tag} <- latest_release_tag(),
         ^version <- data_version_at(tag) do
      {:error,
       """
       Data version #{version} is the one the latest release, #{tag}, carries, so it is \
       not replaced. Run `mix localize.bump_patch_version` and regenerate to publish \
       changed data under a new data version.
       """}
    else
      _unreleased -> :ok
    end
  end

  defp latest_release_tag do
    case git(["tag", "--list", "v*", "--sort=-version:refname"]) do
      {:ok, output} ->
        case String.split(output, "\n", trim: true) do
          [tag | _older] -> {:ok, tag}
          [] -> :none
        end

      :error ->
        :none
    end
  end

  # The same derivation as `Localize.version/0`, from a tag's version files.
  defp data_version_at(tag) do
    with {:ok, cldr_version} <- git(["show", "#{tag}:priv/localize/version"]),
         {:ok, patch_raw} <- git(["show", "#{tag}:priv/localize/localize_patch_version"]) do
      cldr_version = String.trim(cldr_version)

      patch =
        case String.split(String.trim(patch_raw), ":", parts: 2) do
          [^cldr_version, patch] -> patch
          [patch_only] -> patch_only
          _stale -> "0"
        end

      case String.split(cldr_version, ".") do
        [major] -> "v#{major}.0.#{patch}"
        [major, minor | _rest] -> "v#{major}.#{minor}.#{patch}"
      end
    end
  end

  defp git(arguments) do
    case System.cmd("git", arguments, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {_output, _status} -> :error
    end
  end

  # ── Publishing ─────────────────────────────────────────────────

  defp report(plan, options) do
    bytes = plan.files |> Enum.map(fn {_name, path} -> File.stat!(path).size end) |> Enum.sum()

    Mix.shell().info("""
    Dry run: nothing was published.

      #{length(plan.files)} locale files (#{Float.round(bytes / 1_048_576, 1)} MB) match #{@manifest_file}
      and would be uploaded to #{plan.bucket}/#{prefix(plan)}/, skipping any R2 already holds.
      #{if options[:skip_purge], do: "The Cloudflare cache would not be purged.", else: "Their URLs would be purged from the Cloudflare cache."}
      The manifest would be recorded at #{plan.bucket}/#{prefix(plan)}/#{@manifest_record}.

      R2 credentials: #{credentials_status(R2.config())}
      Cloudflare purge credentials: #{credentials_status(purge_config([]))}
    """)
  end

  defp credentials_status({:ok, _config}), do: "set"
  defp credentials_status({:error, message}), do: message

  defp publish(plan, options) do
    with {:ok, r2} <- R2.config(),
         {:ok, purge} <- purge_config(options),
         :new <- recorded(r2, plan),
         :ok <- upload(r2, plan),
         :ok <- purge(purge, plan),
         :ok <- R2.put(r2, plan.bucket, "#{prefix(plan)}/#{@manifest_record}", plan.manifest) do
      Mix.shell().info(
        "Published #{length(plan.files)} locale files to #{plan.bucket}/#{prefix(plan)}/ " <>
          "and recorded their manifest."
      )
    else
      :published ->
        Mix.shell().info(
          "#{plan.bucket}/#{prefix(plan)}/ already records this manifest; nothing to do."
        )

      {:error, message} ->
        Mix.raise(message)
    end
  end

  defp recorded(r2, plan) do
    case R2.get(r2, plan.bucket, "#{prefix(plan)}/#{@manifest_record}") do
      {:ok, bytes} when bytes == plan.manifest -> :published
      {:ok, _other} -> :new
      {:error, :not_found} -> :new
      {:error, message} -> {:error, message}
    end
  end

  defp upload(r2, plan) do
    total = length(plan.files)
    Mix.shell().info("Uploading #{total} locale files to #{plan.bucket}/#{prefix(plan)}/")

    {failures, _progress} =
      plan.files
      |> Task.async_stream(fn {name, path} -> upload_file(r2, plan, name, path) end,
        max_concurrency: @upload_concurrency,
        timeout: :infinity
      )
      |> Enum.reduce({[], %{done: 0, uploaded: 0, current: 0, bytes: 0}}, fn {:ok, result},
                                                                             {failures, progress} ->
        {failures, progress} = tally(result, failures, progress)
        report_progress(progress, total)
        {failures, progress}
      end)

    case Enum.reverse(failures) do
      [] ->
        :ok

      messages ->
        {:error,
         "#{length(messages)} uploads failed:\n#{Enum.join(Enum.take(messages, 5), "\n")}"}
    end
  end

  # A file R2 already holds with the same content is left alone, so that a
  # publish interrupted part way is resumed rather than repeated. R2's ETag
  # for an object written in a single request is the MD5 of its content.
  defp upload_file(r2, plan, name, path) do
    key = "#{prefix(plan)}/#{name}"
    body = File.read!(path)
    md5 = :crypto.hash(:md5, body) |> Base.encode16(case: :lower)

    case R2.etag(r2, plan.bucket, key) do
      {:ok, ^md5} ->
        :current

      _absent_or_different ->
        with :ok <- R2.put(r2, plan.bucket, key, body), do: {:uploaded, byte_size(body)}
    end
  end

  defp tally(:current, failures, progress),
    do: {failures, %{progress | done: progress.done + 1, current: progress.current + 1}}

  defp tally({:uploaded, bytes}, failures, progress) do
    {failures,
     %{
       progress
       | done: progress.done + 1,
         uploaded: progress.uploaded + 1,
         bytes: progress.bytes + bytes
     }}
  end

  defp tally({:error, message}, failures, progress),
    do: {[message | failures], %{progress | done: progress.done + 1}}

  # A line every `@progress_every` files and one for the last, since an
  # upload of the whole set takes minutes.
  defp report_progress(%{done: done} = progress, total)
       when rem(done, @progress_every) == 0 or done == total do
    Mix.shell().info(
      "  #{done}/#{total}: #{progress.uploaded} uploaded " <>
        "(#{Float.round(progress.bytes / 1_048_576, 1)} MB), #{progress.current} already current"
    )
  end

  defp report_progress(_progress, _total), do: :ok

  defp prefix(plan), do: "#{@prefix}/#{plan.version}"

  # ── The Cloudflare cache ───────────────────────────────────────

  defp purge_config(options) do
    if options[:skip_purge], do: {:ok, nil}, else: purge_credentials()
  end

  defp purge_credentials do
    with token when is_binary(token) <- System.get_env("ELIXIR_LOCALIZE_CACHE_PURGE_API_TOKEN"),
         zone when is_binary(zone) <- System.get_env("CLOUDFLARE_ZONE_ID"),
         {:zone, true} <- {:zone, Regex.match?(~r/^[0-9a-f]{32}$/, zone)} do
      {:ok, %{token: token, zone: zone}}
    else
      {:zone, false} ->
        {:error, "CLOUDFLARE_ZONE_ID is not a Cloudflare zone ID"}

      nil ->
        {:error,
         "Purging the Cloudflare cache needs ELIXIR_LOCALIZE_CACHE_PURGE_API_TOKEN and CLOUDFLARE_ZONE_ID; " <>
           "--skip-purge publishes without it, and cached copies of replaced files are then " <>
           "served for up to an hour."}
    end
  end

  defp purge(nil, _plan), do: :ok

  defp purge(%{token: token, zone: zone}, plan) do
    base_url = Localize.Locale.Provider.base_url()
    urls = for {name, _path} <- plan.files, do: "#{base_url}/#{plan.version}/#{name}"

    Mix.shell().info("Purging #{length(urls)} URLs from the Cloudflare cache")

    urls
    |> Enum.chunk_every(@purge_batch_size)
    |> Enum.reduce_while(:ok, fn batch, :ok ->
      case purge_batch(token, zone, batch) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  # The URLs are the CDN's and the locale names are a closed set, so the
  # request body is written directly rather than through a JSON encoder.
  defp purge_batch(token, zone, urls) do
    body = ~s({"files":[#{Enum.map_join(urls, ",", &~s("#{&1}"))}]})
    url = String.to_charlist("https://api.cloudflare.com/client/v4/zones/#{zone}/purge_cache")
    headers = [{~c"Authorization", String.to_charlist("Bearer " <> token)}]

    case :httpc.request(:post, {url, headers, ~c"application/json", body}, R2.http_options(),
           body_format: :binary
         ) do
      {:ok, {{_http, 200, _reason}, _headers, response}} ->
        if Regex.match?(~r/"success"\s*:\s*true/, response),
          do: :ok,
          else: {:error, "The Cloudflare cache purge failed: #{response}"}

      {:ok, {{_http, status, reason}, _headers, response}} ->
        {:error, "The Cloudflare cache purge failed: HTTP #{status} #{reason} #{response}"}

      {:error, reason} ->
        {:error, "The Cloudflare cache purge failed: #{inspect(reason)}"}
    end
  end
end
