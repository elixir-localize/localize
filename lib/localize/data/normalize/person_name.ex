defmodule Localize.Data.Normalize.PersonName do
  @moduledoc false

  alias Localize.Utils.Map, as: LMap

  def normalize(content, _locale) do
    person_names =
      content
      |> Map.fetch!("person_names")
      |> Map.delete("sample_name")
      |> LMap.deep_map(fn
        {k, v} ->
          if (k != "formality" && String.starts_with?(k, "formal")) ||
               String.starts_with?(k, "informal") do
            {String.split(k, "_"), v}
          else
            {String.to_atom(k), v}
          end

        other ->
          other
      end)
      |> LMap.deep_map(fn
        {k, v} when k in [:addressing, :monogram, :referring] ->
          formats =
            Enum.group_by(v, fn {key, _value} -> hd(key) end, fn {_key, value} -> value end)

          {k, formats}

        other ->
          other
      end)
      |> LMap.deep_map(fn
        {k, v} when k in ["formal", "informal"] ->
          {String.to_atom(k), Enum.sort(v)}

        {k, v} when k in [:formality, :length] ->
          {k, v}

        other ->
          other
      end)

    Map.put(content, "person_names", person_names)
  end
end
