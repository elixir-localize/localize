defmodule Localize.Data.Normalize.PlaceholderBoundarySpacing do
  @moduledoc false

  # TR35 §Boundary Spacing: `<placeholderBoundarySpacing type="digit-digit"
  # scopes="datetime">` is the character a formatter inserts where field
  # substitution would run two digits together. CLDR's JSON drops the
  # element name and keys the value by its attributes under `characters`,
  # as "datetime-type-digit-digit".
  def normalize(content, _locale) do
    spacing =
      case get_in(content, ["characters", "datetime_type_digit_digit"]) do
        value when is_binary(value) -> %{datetime_digit_digit: value}
        _no_spacing -> %{}
      end

    Map.put(content, "placeholder_boundary_spacing", spacing)
  end
end
