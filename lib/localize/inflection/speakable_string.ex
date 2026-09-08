defmodule Localize.Inflection.SpeakableString do
  @moduledoc """
  A string with an optional distinct spoken form.

  Most values are plain binaries where the printed and spoken forms
  agree. When they differ (for example "boss’" printed but "boss’s"
  spoken) the value is `{print, speak}`.

  """

  @type t :: binary | {binary, binary}

  @doc """
  Returns the printed form.

  ### Arguments

  * `speakable` is a speakable string.

  ### Returns

  * The printed form as a binary.

  ### Examples

      iex> Localize.Inflection.SpeakableString.print("den")
      "den"

      iex> Localize.Inflection.SpeakableString.print({"den", "dén"})
      "den"

  """
  def print(speakable)

  def print({print, _speak}), do: print
  def print(print) when is_binary(print), do: print

  @doc """
  Returns the spoken form.

  ### Arguments

  * `speakable` is a speakable string.

  ### Returns

  * The spoken form as a binary; the printed form when no distinct
    spoken form exists.

  ### Examples

      iex> Localize.Inflection.SpeakableString.speak("den")
      "den"

      iex> Localize.Inflection.SpeakableString.speak({"den", "dén"})
      "dén"

  """
  def speak(speakable)

  def speak({_print, speak}), do: speak
  def speak(print) when is_binary(print), do: print

  @doc """
  Builds a speakable string, collapsing to a binary when both forms
  agree.

  ### Arguments

  * `print` is the printed form.

  * `speak` is the spoken form, or nil when it equals the printed
    form.

  ### Returns

  * A speakable string.

  ### Examples

      iex> Localize.Inflection.SpeakableString.new("cat", "cat")
      "cat"

      iex> Localize.Inflection.SpeakableString.new("den", "dén")
      {"den", "dén"}

  """
  def new(print, speak) when print == speak or is_nil(speak), do: print
  def new(print, speak), do: {print, speak}

  @doc """
  Concatenates two speakable strings.

  ### Arguments

  * `left` is a speakable string.

  * `right` is a speakable string.

  ### Returns

  * The concatenated speakable string, collapsed to a binary when
    the printed and spoken forms agree.

  ### Examples

      iex> Localize.Inflection.SpeakableString.concat("the ", "cat")
      "the cat"

      iex> Localize.Inflection.SpeakableString.concat({"boss’", "boss’s"}, " office")
      {"boss’ office", "boss’s office"}

  """
  def concat(left, right) do
    new(print(left) <> print(right), speak(left) <> speak(right))
  end
end
