defmodule Localize.Test.InstalledLocales do
  @moduledoc false

  # The locales a test of "every locale" walks: those `test/test_helper.exs`
  # lists and downloads before the tests start, whose data is on the machine.
  # They are the same on every machine, in CI and on the maintainer's.
  #
  # Not every locale Localize ships, for two reasons. A locale that is not on
  # the machine is fetched from the CDN when it is first used, a second or
  # two each, so a test over all of `Localize.all_locale_ids/0` ran past
  # ExUnit's sixty seconds on every CI job. And a loaded locale stays in
  # `:persistent_term`, about 1.2 MB each: all 657 beside the rest of the
  # suite fill the VM's literal memory, a gigabyte by default, and the VM
  # stops. The whole set is tested outside the suite, a locale's worth of
  # work at a time.

  @doc false
  @spec all() :: [atom(), ...]
  def all do
    for name <- Application.fetch_env!(:localize, :test_locales),
        {:ok, locale_id} <- [Localize.Locale.cldr_locale_id_from(name)],
        File.exists?(Localize.Locale.Provider.Cache.path(locale_id)),
        uniq: true,
        do: locale_id
  end
end
