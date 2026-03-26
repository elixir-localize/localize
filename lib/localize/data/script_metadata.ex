defmodule Localize.Data.ScriptMetadata do
  @moduledoc """
  Generates the Unicode script-to-subtag mapping ETF file from
  `Script_Metadata.csv`.

  Parses the CSV to build a map from Unicode script names (as
  underscored atoms, e.g. `:hiragana`) to BCP 47 script subtag
  atoms (e.g. `:Hira`).

  """

  @doc """
  Generates the unicode_script_to_subtag_mapping from
  `priv/cldr/external_sources/Script_Metadata.csv`.

  ### Returns

  * A map of `%{script_name_atom => script_code_atom}`.

  """
  def generate_unicode_script_to_subtag_mapping do
    csv_path = Path.join(Localize.Data.external_sources_dir(), "Script_Metadata.csv")

    csv_path
    |> File.read!()
    |> String.split("\n")
    |> Enum.drop(2)
    |> Enum.map(fn line ->
      case String.split(line, ",") do
        [_number, name, code | _rest] ->
          name =
            name
            |> String.replace(" ", "")
            |> Localize.Utils.String.underscore()
            |> String.to_atom()

          code = String.to_atom(code)
          {name, code}

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end
end
