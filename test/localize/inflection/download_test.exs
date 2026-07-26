defmodule Localize.Inflection.DownloadTest do
  # On-demand download wiring in `Localize.Inflection.Locale.resolve/1`:
  # a supported locale whose artifact is not present locally is fetched
  # from the CDN when runtime downloads are permitted, and every failure
  # path degrades to an error tuple rather than raising.
  use ExUnit.Case, async: false

  alias Localize.Inflection.Locale

  @moduletag :capture_log

  setup do
    original = %{
      data_dir: Application.get_env(:localize, :inflection_data_dir),
      allow: Application.get_env(:localize, :allow_runtime_locale_download),
      base_url: Application.get_env(:localize, :inflection_base_url)
    }

    # Point the data directory at an empty location so no supported
    # locale resolves to a local artifact.
    tmp = Path.join(System.tmp_dir!(), "infl_dl_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    Application.put_env(:localize, :inflection_data_dir, tmp)

    on_exit(fn ->
      restore(:inflection_data_dir, original.data_dir)
      restore(:allow_runtime_locale_download, original.allow)
      restore(:inflection_base_url, original.base_url)
      File.rm_rf(tmp)
    end)

    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:localize, key)
  defp restore(key, value), do: Application.put_env(:localize, key, value)

  test "downloads disabled: a supported locale with no local artifact is not-available" do
    Application.put_env(:localize, :allow_runtime_locale_download, false)

    assert {:error, %Localize.InflectionDataNotAvailableError{}} = Locale.resolve(:en)
  end

  test "downloads enabled: an unreachable CDN degrades to an error, never raises" do
    Application.put_env(:localize, :allow_runtime_locale_download, true)
    Application.put_env(:localize, :inflection_base_url, "http://127.0.0.1:1/inflection")

    assert {:error, %Localize.LocaleDownloadError{}} = Locale.resolve(:en)
  end

  test "an unsupported locale is a not-supported error regardless of download settings" do
    Application.put_env(:localize, :allow_runtime_locale_download, true)

    assert {:error, %Localize.InflectionNotSupportedError{}} = Locale.resolve(:"xx-YZ")
  end
end
