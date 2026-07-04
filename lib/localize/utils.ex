defmodule Localize.Utils do
  # Utility functions and namespace for Localize utility submodules.
  #
  # This module provides general-purpose utility functions. Specialized
  # utilities are organized in submodules:
  #
  # * `Localize.Utils.Math` — mathematical operations.
  #
  # * `Localize.Utils.Digits` — number decomposition and digit manipulation.
  #
  # * `Localize.Utils.String` — string transformation utilities.
  #
  # * `Localize.Utils.Enum` — enumerable utilities with lookahead.
  #
  # * `Localize.Utils.Map` — deep map transformation and manipulation.
  #
  # * `Localize.Utils.Helpers` — general-purpose helper functions.
  #
  # * `Localize.Utils.Decimal` — `Decimal` library compatibility layer.
  #
  # * `Localize.Utils.Json` — JSON decoding utilities.
  #
  # * `Localize.Utils.Http` — secure HTTPS downloading.
  #
  @moduledoc false

  @doc """
  Returns the current OTP version as a string.

  ### Returns

  * A string representing the full OTP version (e.g., `"27.0"`),
    or the major release string if the full version cannot be determined.

  ### Examples

      iex> is_binary(Localize.Utils.otp_version())
      true

  """
  @spec otp_version() :: String.t()
  def otp_version do
    major = :erlang.system_info(:otp_release) |> List.to_string()
    vsn_file = Path.join([:code.root_dir(), "releases", major, "OTP_VERSION"])

    try do
      {:ok, contents} = File.read(vsn_file)
      String.split(contents, "\n", trim: true)
    else
      [full] -> full
      _ -> major
    catch
      :error, _ -> major
    end
  end
end
