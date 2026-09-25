defmodule Localize.DateTimeInvalidInputError do
  @moduledoc """
  Exception raised when a date, time, or datetime value does not
  have the fields required for formatting.

  `:type` names the kind of value expected when the value holds none
  of its fields. When a format pattern asks for fields the value cannot
  supply, `:format` is that pattern, `:missing` lists the fields the
  value does not have and `:invalid` the fields it holds with a value
  of the wrong type.

  """

  defexception [:type, :format, missing: [], invalid: []]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{format: format, missing: missing, invalid: invalid})
      when missing != [] or invalid != [] do
    Localize.Exception.safe_message(
      "datetime",
      "The format {$format} cannot be applied to the value: {$problems}.",
      format: inspect(format),
      problems: problems(missing, invalid)
    )
  end

  def message(%__MODULE__{type: :time}) do
    Localize.Exception.safe_message(
      "datetime",
      "Time must have at least one of :hour, :minute, or :second keys."
    )
  end

  def message(%__MODULE__{type: :date}) do
    Localize.Exception.safe_message(
      "datetime",
      "Date must have at least one of :year, :month, or :day keys."
    )
  end

  def message(%__MODULE__{type: :datetime}) do
    Localize.Exception.safe_message(
      "datetime",
      "Datetime must have date and/or time keys."
    )
  end

  def message(%__MODULE__{}) do
    Localize.Exception.safe_message("datetime", "The value cannot be formatted.")
  end

  defp problems(missing, invalid) do
    [{"missing", missing}, {"invalid", invalid}]
    |> Enum.reject(fn {_label, fields} -> fields == [] end)
    |> Enum.map_join("; ", fn {label, fields} ->
      label <> " " <> Enum.map_join(fields, ", ", &inspect/1)
    end)
  end
end
