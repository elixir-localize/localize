defprotocol Localize.LanguageTag.Chars do
  @moduledoc false

  @doc """
  Converts a language tag component to its string representation.

  """
  def to_string(value)
end
