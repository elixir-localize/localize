defmodule Localize.Data.Normalize.Posix do
  @moduledoc false

  # CLDR ships the POSIX `yesstr` and `nostr` messages as colon-separated
  # lists of the forms a locale accepts — `en` is `"yes:y"` and `"no:n"`.
  # TR35 says the stored value carries only the lower-case forms and that a
  # consumer derives the upper-case and abbreviated variants, so the split
  # list is what gets stored and case folding is left to the reader.

  def normalize(content, _locale) do
    posix = %{
      yes: responses(content, "yesstr"),
      no: responses(content, "nostr")
    }

    Map.put(content, "posix", posix)
  end

  defp responses(content, key) do
    case get_in(content, ["posix", "messages", key]) do
      value when is_binary(value) -> String.split(value, ":", trim: true)
      _no_value -> []
    end
  end
end
