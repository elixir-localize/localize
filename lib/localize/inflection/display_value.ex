defmodule Localize.Inflection.DisplayValue do
  @moduledoc false

  # A candidate surface form of a concept: the display string plus
  # the feature constraints known to hold for it (including the
  # "speak" feature when the spoken form differs).

  alias Localize.Inflection.SpeakableString

  defstruct display_string: "", constraints: %{}

  @type t :: %__MODULE__{display_string: binary, constraints: %{optional(binary) => binary}}

  @speak "speak"

  @doc """
  Builds a display value from a speakable string and initial
  constraints.

  """
  def new(value, constraints \\ %{}) do
    print = SpeakableString.print(value)
    speak = SpeakableString.speak(value)

    constraints =
      if speak != print do
        Map.put(constraints, @speak, speak)
      else
        constraints
      end

    %__MODULE__{display_string: print, constraints: constraints}
  end

  @doc """
  Returns the constraint value for `feature`, or nil.

  """
  def feature_value(%__MODULE__{constraints: constraints}, feature) do
    Map.get(constraints, feature)
  end

  @doc """
  Returns the display value as a speakable string.

  """
  def to_speakable_string(%__MODULE__{} = display_value) do
    case Map.get(display_value.constraints, @speak) do
      nil -> display_value.display_string
      speak -> SpeakableString.new(display_value.display_string, speak)
    end
  end

  @doc """
  Replaces the display string with a speakable string, preserving
  the constraint map and updating the speak constraint.

  """
  def replace(%__MODULE__{} = display_value, speakable) do
    print = SpeakableString.print(speakable)
    speak = SpeakableString.speak(speakable)

    constraints =
      if speak != print do
        Map.put(display_value.constraints, @speak, speak)
      else
        Map.delete(display_value.constraints, @speak)
      end

    %__MODULE__{display_string: print, constraints: constraints}
  end
end
