defmodule Localize.UnknownNumberSystemError do
  @moduledoc """
  Exception raised when a number system name is not a known
  CLDR number system.

  """

  defexception [:number_system, :locale, :reason]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{reason: :not_for_locale, number_system: number_system, locale: locale}) do
    Localize.Exception.safe_message(
      "number",
      "The number system {$number_system} is not valid for locale {$locale}.",
      number_system: inspect(number_system),
      locale: inspect(locale)
    )
  end

  def message(%__MODULE__{number_system: number_system}) do
    Localize.Exception.safe_message(
      "number",
      "The number system {$number_system} is not known.",
      number_system: inspect(number_system)
    )
  end
end
