defmodule Mix.Tasks.Localize.Inflection.GenerateHashes do
  @shortdoc "Generates the SHA-256 manifest for inflection data files"

  @moduledoc """
  Generates `priv/localize/inflection_hashes.etf`, the SHA-256
  manifest that `mix localize.download_inflection` verifies
  downloads against.

      mix localize.inflection.generate_hashes

  Hashes the locale artifacts and the pronoun pack under
  `priv/localize/inflection/`.

      mix localize.inflection.generate_hashes --from-cdn

  Downloads each file of the current data version from the CDN and
  hashes those bytes instead — the canonical-bytes discipline for
  when the upload workflow published data built in CI. Commit the
  refreshed manifest before publishing the package.

  """

  use Mix.Task

  alias Localize.Inflection.{Locale, Provider}

  @manifest_path "priv/localize/inflection_hashes.etf"

  @impl Mix.Task
  def run(args) do
    {:ok, _started} = Application.ensure_all_started(:localize)
    {options, _rest} = OptionParser.parse!(args, strict: [from_cdn: :boolean])

    hashes =
      if options[:from_cdn] do
        from_cdn()
      else
        from_local()
      end

    File.write!(@manifest_path, :erlang.term_to_binary(hashes))
    Mix.shell().info("Wrote #{@manifest_path} with #{map_size(hashes)} entries.")
  end

  defp file_names do
    Enum.map(Locale.supported(), &(&1 <> ".etf")) ++ ["pronouns.etf"]
  end

  defp from_local do
    directory = Path.join([File.cwd!(), "priv", "localize", "inflection"])

    for file_name <- file_names(),
        path = Path.join(directory, file_name),
        File.exists?(path),
        into: %{} do
      {file_name, :crypto.hash(:sha256, File.read!(path))}
    end
  end

  defp from_cdn do
    for file_name <- file_names(), into: %{} do
      Mix.shell().info("Hashing #{Provider.file_url(file_name)}")

      case Localize.Utils.Http.get(Provider.file_url(file_name)) do
        {:ok, body} when is_binary(body) ->
          {file_name, :crypto.hash(:sha256, body)}

        other ->
          Mix.raise("Download failed for #{file_name}: #{inspect(other)}")
      end
    end
  end
end
