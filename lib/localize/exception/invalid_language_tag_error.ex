defmodule Localize.InvalidLanguageTagError do
  @moduledoc """
  Exception raised when a language tag fails to parse.

  """

  defexception [:language_tag, :reason]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{language_tag: language_tag, reason: reason}) when not is_nil(reason) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "language_tag",
      "Invalid language tag {$language_tag}: {$reason}.",
      language_tag: inspect(language_tag),
      reason: to_string(reason)
    )
  end

  def message(%__MODULE__{language_tag: language_tag}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "language_tag",
      "Invalid language tag {$language_tag}.",
      language_tag: inspect(language_tag)
    )
  end
end
