defmodule Localize.Data.Normalize.List do
  @moduledoc false

  alias Localize.Utils.Map, as: LMap

  def normalize(content, _locale) do
    lists =
      content
      |> get_in(["list_patterns"])
      |> Enum.map(fn {"list_pattern_type_" <> type, data} ->
        {type, compile_formats(data)}
      end)
      |> Map.new()
      |> LMap.integerize_keys()
      |> LMap.atomize_keys()

    Map.put(content, "list_formats", lists)
  end

  defp compile_formats(formats) do
    Enum.map(formats, fn {key, template} ->
      {key, Localize.Substitution.parse(template)}
    end)
    |> Map.new()
  end
end
