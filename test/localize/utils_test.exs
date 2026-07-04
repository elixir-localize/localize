defmodule Localize.UtilsTest do
  use ExUnit.Case, async: true

  doctest Localize.Utils

  describe "otp_version/0" do
    test "returns a version string beginning with the OTP major release" do
      major = :otp_release |> :erlang.system_info() |> List.to_string()
      version = Localize.Utils.otp_version()

      assert is_binary(version)
      assert String.starts_with?(version, major)
    end
  end
end
