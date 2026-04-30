defmodule Localize.Validity.T.Fields do
  @moduledoc false

  # Static field metadata for the BCP 47 `t` extension.
  #
  # Lives in a leaf module (no SupplementalData / Validity macro
  # dependencies) so that `Localize.LanguageTag.T` can compile-time
  # depend on this module for its struct definition without inheriting
  # `Localize.Validity.T`'s compile-connected cycle.

  @field_mapping %{
    "language" => :language,
    "m0" => :m0,
    "s0" => :s0,
    "d0" => :d0,
    "i0" => :i0,
    "k0" => :k0,
    "t0" => :t0,
    "h0" => :h0,
    "x0" => :x0
  }

  @fields Map.values(@field_mapping)
  @inverse_field_mapping Map.new(@field_mapping, fn {k, v} -> {v, k} end)

  @doc false
  def fields, do: @fields

  @doc false
  def field_mapping, do: @field_mapping

  @doc false
  def inverse_field_mapping, do: @inverse_field_mapping
end
