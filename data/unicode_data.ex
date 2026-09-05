defmodule Localize.Data.UnicodeData do
  @moduledoc false

  # Parses Unicode Character Database text files to generate
  # compact ETF lookup tables for the collation system.

  @unicode_dir "priv/unicode"

  @files [
    {"DerivedCombiningClass.txt", "combining_class.txt"},
    {"DerivedGeneralCategory.txt", "general_category.txt"}
  ]

  @doc """
  Ensures `priv/unicode/` holds UCD property files matching the Unicode
  version CLDR is built against, downloading them if it does not.

  The required version is read from the `# VERSION: UCA=x, UCD=y` header of
  the vendored `FractionalUCA.txt` rather than configured separately. CLDR
  states which UCD it was generated against, so deriving it leaves no second
  version to drift — and drift is exactly what put these files two Unicode
  releases behind the conformance fixtures they are tested against.

  A maintainer who has never run this has no `priv/unicode/` at all, and no
  reason to have the files lying around locally, so the fetch is from
  unicode.org.

  ### Returns

  * `{:ok, :current}` when the vendored files already match.

  * `{:ok, :downloaded}` when they were fetched.

  * `{:error, reason}` when the version could not be determined or a
    download failed.

  """
  @spec ensure_ucd_files() :: {:ok, :current | :downloaded} | {:error, term()}
  def ensure_ucd_files do
    with {:ok, required} <- required_ucd_version() do
      if Enum.all?(@files, fn {_src, dest} -> vendored_version(dest) == required end) do
        IO.puts("UCD property files are at #{required}; nothing to fetch")
        {:ok, :current}
      else
        download_ucd_files(required)
      end
    end
  end

  @doc """
  Returns the UCD version CLDR was generated against, read from the
  `FractionalUCA.txt` header.

  ### Returns

  * `{:ok, version}` such as `{:ok, "18.0.0"}`.

  * `{:error, reason}` when the file or its header is absent.

  """
  @spec required_ucd_version() :: {:ok, String.t()} | {:error, term()}
  def required_ucd_version do
    path = Path.join([File.cwd!(), "priv", "cldr", "FractionalUCA.txt"])

    cond do
      not File.exists?(path) ->
        {:error, "FractionalUCA.txt not found at #{path} — run mix localize.copy_sources first"}

      version = scan_ucd_version(path) ->
        {:ok, version}

      true ->
        {:error, "no `# VERSION: ... UCD=x.y.z` header in #{path}"}
    end
  end

  # `# VERSION: UCA=18.0.0, UCD=18.0.0`
  defp scan_ucd_version(path) do
    path
    |> File.stream!()
    |> Enum.take(10)
    |> Enum.find_value(fn line ->
      case Regex.run(~r/^#\s*VERSION:.*\bUCD=([0-9]+\.[0-9]+\.[0-9]+)/, line) do
        [_, version] -> version
        nil -> nil
      end
    end)
  end

  # `# DerivedCombiningClass-18.0.0.txt`
  defp vendored_version(filename) do
    path = Path.join([File.cwd!(), @unicode_dir, filename])

    if File.exists?(path) do
      path
      |> File.stream!()
      |> Enum.take(1)
      |> Enum.find_value(fn line ->
        case Regex.run(~r/-([0-9]+\.[0-9]+\.[0-9]+)\.txt/, line) do
          [_, version] -> version
          nil -> nil
        end
      end)
    end
  end

  defp download_ucd_files(version) do
    :ssl.start()
    :inets.start()

    base = "https://www.unicode.org/Public/#{version}/ucd/extracted"
    dest_dir = Path.join(File.cwd!(), @unicode_dir)
    File.mkdir_p!(dest_dir)

    Enum.reduce_while(@files, {:ok, :downloaded}, fn {source, dest}, acc ->
      IO.puts("Downloading #{source} (UCD #{version}) ...")

      case http_get("#{base}/#{source}") do
        {:ok, body} ->
          File.write!(Path.join(dest_dir, dest), body)
          IO.puts("  #{byte_size(body)} bytes -> #{@unicode_dir}/#{dest}")
          {:cont, acc}

        {:error, reason} ->
          {:halt, {:error, "download failed for #{base}/#{source}: #{inspect(reason)}"}}
      end
    end)
  end

  defp http_get(url) do
    case :httpc.request(:get, {String.to_charlist(url), []}, [ssl: ssl_options()], []) do
      {:ok, {{_http, status, _reason}, _headers, body}} when status in 200..299 ->
        {:ok, :erlang.list_to_binary(body)}

      {:ok, {{_http, status, reason}, _headers, _body}} ->
        {:error, "HTTP #{status} #{reason}"}

      {:error, reason} ->
        {:error, reason}
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

  @doc """
  Generates the combining class lookup map from
  `DerivedCombiningClass.txt`.

  Returns a map of `%{codepoint => combining_class}` containing
  only non-zero entries. Codepoint ranges are expanded to
  individual entries for O(1) lookup.

  """
  def generate_combining_classes do
    path = Path.join(File.cwd!(), Path.join(@unicode_dir, "combining_class.txt"))

    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.reduce(%{}, fn line, acc ->
      line = line |> String.split("#") |> hd() |> String.trim()

      case parse_combining_class_line(line) do
        nil -> acc
        {_range, 0} -> acc
        {range, class} -> expand_range(range, class, acc)
      end
    end)
  end

  defp parse_combining_class_line(""), do: nil

  defp parse_combining_class_line(line) do
    case String.split(line, ";") do
      [range_str, class_str] ->
        class = class_str |> String.trim() |> String.to_integer()
        range = parse_codepoint_range(String.trim(range_str))
        {range, class}

      _ ->
        nil
    end
  end

  @doc """
  Generates the decimal digit ranges from
  `DerivedGeneralCategory.txt`.

  Returns a sorted list of `{start, finish}` codepoint range
  tuples where the general category is `Nd` (Decimal Number).

  """
  def generate_decimal_digit_ranges do
    path = Path.join(File.cwd!(), Path.join(@unicode_dir, "general_category.txt"))

    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.reduce([], fn line, acc ->
      line = line |> String.split("#") |> hd() |> String.trim()

      case parse_category_line(line) do
        {:ok, range, "Nd"} -> [range | acc]
        _ -> acc
      end
    end)
    |> Enum.sort()
  end

  defp parse_category_line(""), do: nil

  defp parse_category_line(line) do
    case String.split(line, ";") do
      [range_str, category_str] ->
        {:ok, parse_codepoint_range(String.trim(range_str)), String.trim(category_str)}

      _ ->
        nil
    end
  end

  defp parse_codepoint_range(str) do
    case String.split(str, "..") do
      [single] ->
        cp = String.to_integer(single, 16)
        {cp, cp}

      [from, to] ->
        {String.to_integer(from, 16), String.to_integer(to, 16)}
    end
  end

  defp expand_range({start, finish}, class, acc) do
    Enum.reduce(start..finish, acc, fn cp, map ->
      Map.put(map, cp, class)
    end)
  end
end
