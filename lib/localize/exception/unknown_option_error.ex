defmodule Localize.UnknownOptionError do
  @moduledoc """
  Exception returned when an option key is not one the function accepts.

  An unrecognised key is almost always a typo, and silently ignoring it turns
  a mistake into a wrong-looking result with nothing to trace it to: asking
  for `currancy: :USD` and receiving a bare number reports success. The
  message names the nearest known option where there is one.

  """

  defexception [:option, :suggestion, :known]

  @typedoc """
  The unrecognised option, the nearest known option if one is close enough,
  and the full set of options the function accepts.

  """
  @type t :: %__MODULE__{
          option: atom(),
          suggestion: atom() | nil,
          known: [atom()]
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{option: option, suggestion: nil}) do
    Localize.Exception.safe_message(
      "locale",
      "{$option} is not a known option",
      option: inspect(option)
    )
  end

  def message(%__MODULE__{option: option, suggestion: suggestion}) do
    Localize.Exception.safe_message(
      "locale",
      "{$option} is not a known option. Did you mean {$suggestion}?",
      option: inspect(option),
      suggestion: inspect(suggestion)
    )
  end
end
