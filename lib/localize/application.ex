defmodule Localize.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type \\ :normal, _args \\ []) do
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
end
