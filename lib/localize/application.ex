defmodule Localize.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type \\ :normal, _args \\ []) do
    Localize.Supervisor.start_link([])
  end
end
