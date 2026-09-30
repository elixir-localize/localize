defmodule Localize.Application do
  @moduledoc false

  use Application

  # Localize's data must be readable before anything loads it. Inside an
  # escript that means extracting it from the escript's archive, and an
  # escript built without it cannot start: the application then stops with
  # the reason, rather than each process crashing on its first read.
  @impl true
  def start(_type \\ :normal, _args \\ []) do
    case Localize.Priv.prepare() do
      {:ok, _dir} -> Localize.Supervisor.start_link([])
      {:error, message} -> {:error, message}
    end
  end
end
