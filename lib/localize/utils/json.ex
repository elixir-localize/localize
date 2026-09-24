defmodule Localize.Utils.Json do
  # JSON decoding utilities wrapping the OTP `:json` module.
  #
  # Provides a `Jason`-compatible `decode!/1,2` interface suitable
  # for decoding JSON data in Localize. Uses the built-in `:json`
  # module available in OTP 27+.
  #
  @moduledoc false

  @doc """
  Decodes a JSON string into an Elixir term.

  JSON `null` values are decoded as `nil`, and object keys are
  strings. There is no option to decode keys as atoms: a key from
  untrusted JSON must never become one.

  ### Arguments

  * `string` — a JSON-encoded string or charlist.

  ### Returns

  * The decoded Elixir term.

  ### Examples

      iex> Localize.Utils.Json.decode!(~s({"foo": 1}))
      %{"foo" => 1}

      iex> Localize.Utils.Json.decode!(~s({"bar": null}))
      %{"bar" => nil}

  """
  @spec decode!(String.t() | charlist()) :: term()
  def decode!(string) when is_binary(string) do
    case :json.decode(string, :ok, %{null: nil}) do
      {json, :ok, ""} -> json
      {_json, :ok, rest} -> raise_trailing_data!(rest)
    end
  end

  def decode!(charlist) when is_list(charlist) do
    charlist
    |> :erlang.iolist_to_binary()
    |> decode!()
  end

  @spec raise_trailing_data!(binary()) :: no_return()
  defp raise_trailing_data!(rest) do
    raise ArgumentError,
          "unexpected trailing data after the JSON document: " <>
            inspect(rest, printable_limit: 50)
  end
end
