defmodule Localize.Validity.U.Fields do
  @moduledoc false

  # Static field metadata for the BCP 47 `u` extension.
  #
  # Lives in a leaf module (no SupplementalData / Validity macro
  # dependencies) so that `Localize.LanguageTag.U` can compile-time
  # depend on this module for its struct definition without inheriting
  # `Localize.Validity.U`'s compile-connected cycle.

  @field_mapping %{
    "ca" => :ca,
    "cf" => :cf,
    "co" => :co,
    "cu" => :cu,
    "dx" => :dx,
    "em" => :em,
    "fw" => :fw,
    "hc" => :hc,
    "ka" => :ka,
    "kb" => :kb,
    "kc" => :kc,
    "kf" => :kf,
    "kh" => :kh,
    "kk" => :kk,
    "kn" => :kn,
    "kr" => :kr,
    "ks" => :ks,
    "kv" => :kv,
    "lb" => :lb,
    "lw" => :lw,
    "ms" => :ms,
    "mu" => :mu,
    "nu" => :nu,
    "rg" => :rg,
    "sd" => :sd,
    "ss" => :ss,
    "tz" => :tz,
    "va" => :va,
    "vt" => :vt
  }

  @fields Map.values(@field_mapping) |> Enum.sort()
  @inverse_field_mapping Map.new(@field_mapping, fn {k, v} -> {v, k} end)

  @doc false
  def fields, do: @fields

  @doc false
  def field_mapping, do: @field_mapping

  @doc false
  def inverse_field_mapping, do: @inverse_field_mapping
end
