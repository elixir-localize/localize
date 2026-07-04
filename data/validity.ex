defmodule Localize.Data.Validity do
  @moduledoc """
  Generates validity ETF files from CLDR validity XML and BCP47 XML sources.

  Produces ETF files for language, script, territory, subdivision,
  variant, and unit validity data, plus BCP47 U and T extension
  validity data.

  """

  import SweetXml

  alias Localize.Utils.Map, as: LMap

  @validity_types %{
    "region.xml" => "validity_territories",
    "language.xml" => "validity_languages",
    "script.xml" => "validity_scripts",
    "subdivision.xml" => "validity_subdivisions",
    "variant.xml" => "validity_variants",
    "unit.xml" => "validity_units"
  }

  @u_files [
    "collation.xml",
    "calendar.xml",
    "currency.xml",
    "measure.xml",
    "number.xml",
    "segmentation.xml",
    "timezone.xml",
    "variant.xml"
  ]

  @t_files [
    "transform.xml",
    "transform_hybrid.xml",
    "transform_ime.xml",
    "transform_keyboard.xml",
    "transform_mt.xml",
    "transform-destination.xml"
  ]

  @doc """
  Generates all validity and BCP47 ETF files.

  Writes files to `priv/localize/validity/`.

  ### Returns

  * `:ok` on success.

  """
  def generate_all do
    output_dir = validity_output_dir()
    File.rm_rf!(output_dir)
    File.mkdir_p!(output_dir)

    # Generate validity files from XML
    for {xml_file, etf_name} <- @validity_types do
      IO.puts("Generating #{etf_name}.etf...")
      data = generate_validity(xml_file, etf_name)
      save(etf_name, data, output_dir)
    end

    # Generate BCP47 U and T extension files
    IO.puts("Generating validity_u.etf...")
    u_data = generate_bcp47_u()
    save("validity_u", u_data, output_dir)

    IO.puts("Generating validity_t.etf...")
    t_data = generate_bcp47_t()
    save("validity_t", t_data, output_dir)

    IO.puts("All #{map_size(@validity_types) + 2} validity ETF files generated.")
    :ok
  end

  @doc """
  Generates validity data from a CLDR validity XML file.

  Returns a map of status strings to lists of code strings.

  """
  def generate_validity(xml_file, etf_name) do
    validity_dir = Path.join(File.cwd!(), "priv/cldr/validity")

    validity_dir
    |> Path.join(xml_file)
    |> File.read!()
    |> String.replace(~r/<!DOCTYPE.*>\n/, "")
    |> xpath(~x"//id"l,
      status: ~x"./@idStatus"s,
      data: ~x"./text()"s
    )
    |> Enum.map(fn map -> {map.status, String.split(map.data, ~r/\s/, trim: true)} end)
    |> Map.new()
    |> maybe_transform_units(etf_name)
    |> LMap.atomize_keys()
    |> Map.new()
  end

  @doc """
  Generates BCP47 U extension validity data from BCP47 XML files.

  """
  def generate_bcp47_u do
    bcp47_dir = Path.join(File.cwd!(), "priv/cldr/bcp47")

    Enum.reduce(@u_files, [], fn file, acc ->
      acc ++ extract_u(bcp47_dir, file)
    end)
    |> Enum.map(&flatten_u_list/1)
    |> Map.new()
    |> split_timezone_names()
    |> LMap.deep_map(fn
      k when is_binary(k) -> k
      {k, "quaternary quarternary"} -> {k, "quaternary"}
      {k, {:deprecated, v}} -> {underscore(k), {:deprecated, underscore(v)}}
      {k, v} when is_binary(v) -> {underscore(k), underscore(v)}
      {k, v} -> {underscore(k), v}
    end)
  end

  @doc """
  Generates BCP47 T extension validity data from BCP47 XML files.

  """
  def generate_bcp47_t do
    bcp47_dir = Path.join(File.cwd!(), "priv/cldr/bcp47")

    Enum.reduce(@t_files, [], fn file, acc ->
      acc ++ extract_t(bcp47_dir, file)
    end)
    |> Enum.map(&flatten_t_list/1)
    |> Map.new()
    |> LMap.deep_map(fn
      k when is_binary(k) -> k
      {k, v} when is_binary(v) -> {underscore(k), underscore(v)}
      {k, v} -> {underscore(k), v}
    end)
  end

  # ── Private helpers ─────────────────────────────────────────────

  defp validity_output_dir do
    Path.join(File.cwd!(), "priv/localize/validity")
  end

  defp save(name, data, output_dir) do
    path = Path.join(output_dir, "#{name}.etf")
    File.write!(path, :erlang.term_to_binary(data))
  end

  defp maybe_transform_units(data, "validity_units") do
    Enum.map(data, fn {status, list} ->
      {status, Enum.map(list, &strip_unit_category/1)}
    end)
    |> Map.new()
  end

  defp maybe_transform_units(data, _name), do: data

  defp strip_unit_category(value) do
    case String.split(value, "-", parts: 2) do
      [value] -> value
      [_category, unit] -> underscore(unit)
    end
  end

  defp extract_u(bcp47_dir, file) do
    bcp47_dir
    |> Path.join(file)
    |> File.read!()
    |> String.replace(~r/<!DOCTYPE.*>\n/, "")
    |> xpath(~x"//keyword/key"l,
      name: ~x"./@name"s,
      valid: [
        ~x"./type"l,
        name: ~x"./@name"s,
        alias: ~x"./@alias"s,
        deprecated: ~x"./@deprecated"s,
        preferred: ~x"./@preferred"s
      ]
    )
  end

  defp extract_t(bcp47_dir, file) do
    bcp47_dir
    |> Path.join(file)
    |> File.read!()
    |> String.replace(~r/<!DOCTYPE.*>\n/, "")
    |> xpath(~x"//keyword/key"l,
      name: ~x"./@name"s,
      valid: [~x"./type"l, name: ~x"./@name"s]
    )
  end

  defp flatten_u_list(%{name: name, valid: valid}) do
    {name, flatten_u_valid(valid)}
  end

  # A deprecated type with a preferred replacement is tagged so the
  # runtime accepts it for decoding but never selects it when
  # encoding — `islamicc` decodes to islamic_civil, while encoding
  # emits "islamic-civil". Deprecated types without a `preferred`
  # attribute (some timezone ids) keep their alias behaviour.
  defp flatten_u_valid(list) do
    list
    |> Enum.map(fn
      %{name: name, deprecated: "true", preferred: preferred} when preferred != "" ->
        {name, {:deprecated, preferred}}

      %{name: name, alias: ""} ->
        {name, nil}

      %{name: name, alias: aliass} ->
        {name, aliass}
    end)
    |> Map.new()
  end

  defp flatten_t_list(%{name: name, valid: valid}) do
    {name, flatten_t_valid(valid)}
  end

  defp flatten_t_valid(list) do
    Enum.map(list, fn %{name: name} -> name end)
  end

  defp split_timezone_names(map) do
    tz =
      map
      |> Map.fetch!("tz")
      |> Enum.map(fn
        {k, nil} -> {k, nil}
        {k, v} -> {k, String.split(v)}
      end)
      |> Map.new()

    Map.put(map, "tz", tz)
  end

  defp underscore(string) when is_binary(string) do
    String.replace(string, "-", "_")
  end
end
