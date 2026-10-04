defmodule Localize.Test.InstalledLocales do
  @moduledoc false

  # The locales whose data is on this machine. That is every locale Localize
  # ships where they have all been generated or downloaded, as on the
  # maintainer's machine, and in CI the locales `test/test_helper.exs`
  # downloads before the tests start.
  #
  # A test that walks every locale walks these. A locale that is not on the
  # machine is fetched from the CDN when it is first used, a second or two
  # each, so a test over all of `Localize.all_locale_ids/0` ran past
  # ExUnit's sixty seconds on every CI job.

  @doc false
  @spec all() :: [atom(), ...]
  def all do
    Enum.filter(Localize.all_locale_ids(), fn locale_id ->
      File.exists?(Localize.Locale.Provider.Cache.path(locale_id))
    end)
  end
end
