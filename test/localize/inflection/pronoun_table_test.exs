defmodule Localize.Inflection.PronounTableTest do
  # Pronoun tables as a user who has downloaded only the zh inflection
  # data finds them: the zh artifact alone in the data directory and no
  # runtime downloads. Every table ships inside an artifact, so nothing
  # else on disk is consulted, and a table whose data is not there is an
  # error rather than a crash.
  use ExUnit.Case, async: false

  alias Localize.Inflection.{DataDir, PronounConcept}

  setup do
    original = %{
      data_dir: Application.get_env(:localize, :inflection_data_dir),
      allow: Application.get_env(:localize, :allow_runtime_locale_download)
    }

    data_dir = Path.join(System.tmp_dir!(), "infl_zh_#{System.unique_integer([:positive])}")
    File.mkdir_p!(data_dir)
    File.cp!(DataDir.path("zh.etf"), Path.join(data_dir, "zh.etf"))

    Application.put_env(:localize, :inflection_data_dir, data_dir)
    Application.put_env(:localize, :allow_runtime_locale_download, false)

    on_exit(fn ->
      restore(:inflection_data_dir, original.data_dir)
      restore(:allow_runtime_locale_download, original.allow)
      File.rm_rf(data_dir)
    end)

    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:localize, key)
  defp restore(key, value), do: Application.put_env(:localize, key, value)

  # The expected pronouns are the upstream pronoun_zh_Hant.csv rows
  # `你,second,masculine` and `妳,second,feminine`; the Simplified
  # table has only `你,second`.
  test "zh-TW takes the Traditional Chinese table that ships in the zh artifact" do
    assert {:ok, %PronounConcept{table_locale: "zh_Hant"}} = PronounConcept.new(:"zh-TW")

    assert Localize.Inflection.pronoun(:"zh-TW", person: :second, gender: :feminine) ==
             {:ok, "妳"}

    assert Localize.Inflection.pronoun(:"zh-TW", person: :second, gender: :masculine) ==
             {:ok, "你"}
  end

  test "zh-HK, whose table is Cantonese, reports the yue data as missing rather than raising" do
    assert {:error, %Localize.InflectionDataNotAvailableError{locale: "yue"}} =
             Localize.Inflection.pronoun(:"zh-HK", person: :first)
  end
end
