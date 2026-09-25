defmodule Localize.Validity.Language do
  @moduledoc false

  use Localize.Validity, :languages
  @behaviour Localize.Validity

  def validate(nil) do
    {:ok, nil, nil}
  end

  def validate(code) when is_binary(code) or is_atom(code) do
    code
    |> to_string()
    |> String.downcase()
    |> valid()
    |> case do
      {:error, _} -> {:error, code}
      other -> other
    end
  end

  def validate(code), do: {:error, code}

  def normalize(code) when is_binary(code) do
    String.downcase(code)
  end

  def normalize(nil) do
    nil
  end
end
