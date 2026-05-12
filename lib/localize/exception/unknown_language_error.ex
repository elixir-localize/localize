defmodule Localize.UnknownLanguageError do
  @moduledoc """
  Exception raised when a language code cannot be found in
  the locale display name data.

  """

  defexception [:language]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{language: language}) do
    Localize.Exception.safe_message(
      "locale",
      "The language {$language} is not known.",
      language: inspect(language)
    )
  end
end
