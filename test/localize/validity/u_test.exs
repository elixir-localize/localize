defmodule Localize.Validity.UTest do
  use ExUnit.Case, async: true

  alias Localize.Validity.U
  alias Localize.Validity.U.Fields

  describe "fields/0 and field_mapping/0" do
    test "fields covers every u extension key" do
      assert U.fields() == [
               :ca,
               :cf,
               :co,
               :cu,
               :dx,
               :em,
               :fw,
               :hc,
               :ka,
               :kb,
               :kc,
               :kf,
               :kh,
               :kk,
               :kn,
               :kr,
               :ks,
               :kv,
               :lb,
               :lw,
               :ms,
               :mu,
               :nu,
               :rg,
               :sd,
               :ss,
               :tz,
               :va,
               :vt
             ]
    end

    test "field_mapping maps BCP 47 string keys to struct field atoms" do
      mapping = U.field_mapping()
      assert mapping["ca"] == :ca
      assert mapping["tz"] == :tz
      assert map_size(mapping) == 29
    end

    test "Fields.inverse_field_mapping/0 inverts the field mapping" do
      inverse = Fields.inverse_field_mapping()
      assert inverse[:ca] == "ca"
      assert map_size(inverse) == map_size(Fields.field_mapping())
    end
  end

  describe "decode/2 value aliases" do
    test "resolves collation aliases to their long form" do
      assert U.decode("co", "phonebk") == {:ok, {:co, :phonebook}}
      assert U.decode("co", "dict") == {:ok, {:co, :dictionary}}
      assert U.decode("co", "trad") == {:ok, {:co, :traditional}}
    end

    test "resolves measurement system aliases" do
      assert U.decode("ms", "uksystem") == {:ok, {:ms, :imperial}}
      assert U.decode("ms", "metric") == {:ok, {:ms, :metric}}
    end

    test "resolves collation strength aliases" do
      assert U.decode("ks", "level1") == {:ok, {:ks, :primary}}
      assert U.decode("ks", "identic") == {:ok, {:ks, :identical}}
    end

    test "resolves boolean aliases to yes and no" do
      assert U.decode("kn", "true") == {:ok, {:kn, :yes}}
      assert U.decode("kb", "false") == {:ok, {:kb, :no}}
    end

    test "resolves the alternate handling alias" do
      assert U.decode("ka", "noignore") == {:ok, {:ka, :non_ignorable}}
    end

    test "decodes values that have no alias unchanged" do
      assert U.decode("hc", "h23") == {:ok, {:hc, :h23}}
      assert U.decode("fw", "mon") == {:ok, {:fw, :mon}}
      assert U.decode("em", "emoji") == {:ok, {:em, :emoji}}
      assert U.decode("lb", "strict") == {:ok, {:lb, :strict}}
      assert U.decode("lw", "phrase") == {:ok, {:lw, :phrase}}
      assert U.decode("ss", "standard") == {:ok, {:ss, :standard}}
      assert U.decode("va", "posix") == {:ok, {:va, :posix}}
      assert U.decode("mu", "celsius") == {:ok, {:mu, :celsius}}
      assert U.decode("kv", "space") == {:ok, {:kv, :space}}
      assert U.decode("cf", "account") == {:ok, {:cf, :account}}
      assert U.decode("nu", "thai") == {:ok, {:nu, :thai}}
    end
  end

  describe "decode/2 currency" do
    test "upcases currency codes" do
      assert U.decode("cu", "usd") == {:ok, {:cu, :USD}}
      assert U.decode("cu", "aud") == {:ok, {:cu, :AUD}}
    end

    test "rejects unknown currency codes" do
      assert {:error, %Localize.InvalidSubtagError{key: "cu"}} = U.decode("cu", "zzy")
    end
  end

  describe "decode/2 timezones" do
    test "resolves a short id to the canonical IANA name" do
      assert U.decode("tz", "ausyd") == {:ok, {:tz, "Australia/Sydney"}}
      assert U.decode("tz", "usnyc") == {:ok, {:tz, "America/New_York"}}
    end

    test "resolves a deprecated id through its preferred replacement" do
      assert U.decode("tz", "est5edt") == {:ok, {:tz, "America/New_York"}}
    end
  end

  describe "decode/2 region and subdivision overrides" do
    test "decodes an rg territory override with the zzzz filler" do
      assert U.decode("rg", "uszzzz") == {:ok, {:rg, :US}}
    end

    test "decodes an rg subdivision override" do
      assert U.decode("rg", "gbeng") == {:ok, {:rg, :gbeng}}
    end

    test "decodes an sd subdivision" do
      assert U.decode("sd", "usca") == {:ok, {:sd, :usca}}
    end

    test "rejects an unknown subdivision" do
      assert {:error, %Localize.InvalidSubtagError{key: "sd"}} = U.decode("sd", "zzublah")
    end
  end

  describe "decode/2 script lists (dx and kr)" do
    test "decodes a single dx script" do
      assert U.decode("dx", "thai") == {:ok, {:dx, :Thai}}
    end

    test "decodes a dx script list" do
      assert U.decode("dx", ["thai", "latn"]) == {:ok, {:dx, [:Latn, :Thai]}}
    end

    test "rejects a dx list containing an invalid script" do
      assert {:error, %Localize.InvalidSubtagError{key: "dx"}} =
               U.decode("dx", ["thai", "xxxx"])
    end

    test "decodes a kr reorder code" do
      assert U.decode("kr", "digit") == {:ok, {:kr, [:digit]}}
    end

    test "decodes a kr script value" do
      assert U.decode("kr", "latn") == {:ok, {:kr, [:Latn]}}
    end

    test "decodes a kr list preserving order" do
      assert U.decode("kr", ["latn", "digit"]) == {:ok, {:kr, [:Latn, :digit]}}
    end

    test "rejects a kr list containing an invalid value" do
      assert {:error, %Localize.InvalidSubtagError{key: "kr"}} =
               U.decode("kr", ["latn", "bogusxxx"])
    end
  end

  describe "decode/2 errors" do
    test "returns an InvalidSubtagError for an invalid value" do
      assert {:error, %Localize.InvalidSubtagError{} = exception} = U.decode("hc", "h25")
      assert exception.key == "hc"
      assert exception.value == "h25"
    end

    test "returns an InvalidSubtagError for an unknown key" do
      assert {:error, %Localize.InvalidSubtagError{key: "zz"}} = U.decode("zz", "abc")
    end
  end

  describe "encode/2" do
    test "encodes an IANA timezone back to its short id" do
      assert U.encode(:tz, "Australia/Sydney") == {"tz", "ausyd"}
      assert U.encode(:tz, "America/New_York") == {"tz", "usnyc"}
    end

    test "encodes an rg territory with the zzzz filler" do
      assert U.encode(:rg, :US) == {"rg", "uszzzz"}
    end

    test "encodes an rg subdivision without the filler" do
      assert U.encode(:rg, :gbeng) == {"rg", "gbeng"}
    end

    test "encodes currency codes in lowercase" do
      assert U.encode(:cu, :USD) == {"cu", "usd"}
    end

    test "encodes aliased values with their BCP 47 short form" do
      assert U.encode(:ms, :imperial) == {"ms", "uksystem"}
      assert U.encode(:ks, :primary) == {"ks", "level1"}
      assert U.encode(:ka, :non_ignorable) == {"ka", "noignore"}
      assert U.encode(:co, :phonebook) == {"co", "phonebk"}
      assert U.encode(:kn, :yes) == {"kn", "true"}
    end

    test "encodes a kr reorder list as hyphen-joined values" do
      assert U.encode(:kr, [:Latn, :digit]) == {"kr", "latn-digit"}
    end

    test "encodes dx scripts in lowercase" do
      assert U.encode(:dx, :Thai) == {"dx", "thai"}
      assert U.encode(:dx, [:Thai, :Latn]) == {"dx", "thai-latn"}
    end

    test "accepts string keys" do
      assert U.encode("hc", :h11) == {"hc", "h11"}
    end
  end

  describe "error constructors" do
    test "invalid_value_error/2 builds an InvalidSubtagError" do
      assert %Localize.InvalidSubtagError{key: "hc", value: "h99", reason: nil} =
               U.invalid_value_error("hc", "h99")
    end

    test "invalid_key_error/1 builds an InvalidSubtagError with reason" do
      assert %Localize.InvalidSubtagError{key: "zz", value: nil, reason: :invalid_key} =
               U.invalid_key_error("zz")
    end
  end
end
