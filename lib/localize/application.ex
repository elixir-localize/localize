defmodule Localize.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type \\ :normal, _args \\ []) do
    ensure_locale_cache_table()

    children = [
      Localize.DataLoader,
      Localize.Locale.Loader,
      Localize.Collation.Table,
      Localize.Collation.Han,
      Localize.Currency.Store
    ]

    options = [strategy: :one_for_one, name: Localize.Supervisor]
    Supervisor.start_link(children, options)
  end

  defp ensure_locale_cache_table do
    if :ets.whereis(:localize_locale_cache) == :undefined do
      :ets.new(:localize_locale_cache, [
        :set,
        :public,
        :named_table,
        read_concurrency: true
      ])
    end
  end
end
