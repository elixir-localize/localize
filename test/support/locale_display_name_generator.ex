defmodule Localize.LocaleDisplayNameGenerator do
  @moduledoc false

  def data do
    Path.join(__DIR__, "data/locale_display_names.txt")
    |> Path.expand()
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reject(fn {elem, _index} -> elem == "" or String.starts_with?(elem, "#") end)
    |> Enum.map(fn {line, index} ->
      line
      |> String.split(";")
      |> Enum.map(&String.trim/1)
      |> Enum.map(&locale_name_from_posix/1)
      |> List.insert_at(0, index)
    end)
    |> insert_locale_and_options()
    |> Enum.reverse()
  end

  defp locale_name_from_posix(nil), do: nil

  defp locale_name_from_posix(name) when is_binary(name) do
    String.replace(name, "_", "-")
  end

  defp insert_locale_and_options(list) do
    {acc, _, _} =
      Enum.reduce(list, {[], nil, nil}, fn
        [line, locale, display], {acc, test_locale, language_display} ->
          {[[line, test_locale, language_display, locale, display] | acc], test_locale,
           language_display}

        [_line, option], {acc, locale, language_display} ->
          case String.split(option, "=") do
            ["@locale", new_locale] ->
              {acc, new_locale, language_display}

            ["@languageDisplay", new_display] ->
              {acc, locale, String.to_atom(new_display)}
          end
      end)

    acc
  end
end
