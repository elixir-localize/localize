defmodule Localize.Utils.Json do
  @moduledoc """
  JSON decoding utilities wrapping the OTP `:json` module.

  Provides a `Jason`-compatible `decode!/1,2` interface suitable
  for decoding JSON data in Localize. Uses the built-in `:json`
  module available in OTP 27+.

  """

  @doc """
  Decodes a JSON string into an Elixir term.

  JSON `null` values are decoded as `nil`. By default, object keys
  are strings. Pass `keys: :atoms` to decode keys as atoms.

  ### Arguments

  * `string` — a JSON-encoded string or charlist.

  ### Options

  * `:keys` — when set to `:atoms`, decodes object keys as atoms.

  ### Returns

  * The decoded Elixir term.

  ### Examples

      iex> Localize.Utils.Json.decode!(~s({"foo": 1}))
      %{"foo" => 1}

      iex> Localize.Utils.Json.decode!(~s({"foo": 1}), keys: :atoms)
      %{foo: 1}

      iex> Localize.Utils.Json.decode!(~s({"bar": null}))
      %{"bar" => nil}

  """
  @spec decode!(String.t() | charlist()) :: term()
  def decode!(string) when is_binary(string) do
    {json, :ok, ""} = :json.decode(string, :ok, %{null: nil})
    json
  end

  def decode!(charlist) when is_list(charlist) do
    charlist
    |> :erlang.iolist_to_binary()
    |> decode!()
  end

  @spec decode!(String.t() | charlist(), keyword()) :: term()
  def decode!(string, keys: :atoms) when is_binary(string) do
    push = fn key, value, accumulator ->
      [{String.to_atom(key), value} | accumulator]
    end

    decoders = %{
      null: nil,
      object_push: push
    }

    {json, :ok, ""} = :json.decode(string, :ok, decoders)
    json
  end

  def decode!(charlist, options) when is_list(charlist) do
    charlist
    |> :erlang.iolist_to_binary()
    |> decode!(options)
  end
end
