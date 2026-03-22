defmodule Localize.UnknownNumberSystemError do
  @moduledoc """
  Exception raised when a number system name is not a known
  CLDR number system.

  """

  defexception [:number_system]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{number_system: number_system}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "number",
      "The number system %{number_system} is not known.",
      number_system: inspect(number_system)
    )
  end
end
