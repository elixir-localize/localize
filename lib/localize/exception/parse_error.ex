defmodule Localize.ParseError do
  @moduledoc """
  Exception raised when a language tag or unit identifier cannot be parsed.

  """

  defexception [:input, :reason]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{input: input, reason: reason}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "language_tag",
      "Could not parse {$input}: {$reason}",
      input: inspect(input),
      reason: reason
    )
  end
end
