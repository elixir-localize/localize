defmodule Localize.LocaleMatchError do
  @moduledoc """
  Exception raised when no matching locale can be found
  within the specified distance threshold.

  """

  defexception [:desired, :threshold]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{desired: desired, threshold: threshold}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "language_tag",
      "No matching locale found for {$desired} within distance {$threshold}",
      desired: inspect(desired),
      threshold: threshold
    )
  end
end
