defmodule Localize.Test.ScriptedHttpServer do
  @moduledoc false

  # A local HTTP server that answers each request with the next scripted
  # response and records the requests it received. It is plain `:gen_tcp`
  # on 127.0.0.1, so a test can make the CDN fail on cue without any
  # network traffic or dependency.
  #
  # Each response is `{status, headers, body}`. A request beyond the
  # script is answered with a 500, which a test counting requests notices.

  @doc """
  Starts a server for `responses` and returns a map with its `:url`.
  """
  def start(responses, path \\ "/locale.etf") do
    {:ok, listen} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, ip: {127, 0, 0, 1}])

    {:ok, port} = :inet.port(listen)
    {:ok, agent} = Agent.start_link(fn -> %{responses: responses, requests: []} end)
    acceptor = spawn_link(fn -> accept(listen, agent) end)
    :ok = :gen_tcp.controlling_process(listen, acceptor)

    %{url: "http://127.0.0.1:#{port}#{path}", port: port, agent: agent}
  end

  @doc """
  Returns the raw requests the server received, oldest first.
  """
  def requests(%{agent: agent}) do
    agent |> Agent.get(& &1.requests) |> Enum.reverse()
  end

  defp accept(listen, agent) do
    case :gen_tcp.accept(listen) do
      {:ok, socket} ->
        with {:ok, request} <- read_request(socket, "") do
          {status, headers, body} = next_response(agent, request)
          :ok = :gen_tcp.send(socket, response(status, headers, body))
        end

        :gen_tcp.close(socket)
        accept(listen, agent)

      {:error, _closed} ->
        :ok
    end
  end

  defp read_request(socket, received) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, data} ->
        received = received <> data

        if String.contains?(received, "\r\n\r\n"),
          do: {:ok, received},
          else: read_request(socket, received)

      error ->
        error
    end
  end

  defp next_response(agent, request) do
    Agent.get_and_update(agent, fn
      %{responses: [next | rest], requests: seen} = state ->
        {next, %{state | responses: rest, requests: [request | seen]}}

      %{responses: [], requests: seen} = state ->
        {{500, [], "unscripted request"}, %{state | requests: [request | seen]}}
    end)
  end

  defp response(status, headers, body) do
    header_lines = Enum.map_join(headers, fn {name, value} -> "#{name}: #{value}\r\n" end)

    "HTTP/1.1 #{status} Scripted\r\n" <>
      "content-length: #{byte_size(body)}\r\n" <>
      "connection: close\r\n" <>
      header_lines <> "\r\n" <> body
  end
end
