defmodule Localize.Validity do
  @moduledoc false

  @doc """
  Normalizes a language tag field.
  """
  @callback normalize(String.t() | atom()) :: String.t() | atom()

  @doc """
  Validates a language tag field
  """
  @callback validate(String.t() | atom()) :: {:ok, term, atom()} | {:error, String.t()}

  defmacro __using__(type) do
    validity_data = Localize.SupplementalData.validity(type)
    Localize.Validity.generate_validity_checks(type, validity_data)
  end

  # A single map literal with one lookup function instead of a
  # per-code clause fan: `code in [thousands of codes]` guards
  # compiled the languages and subdivisions modules in ~11s each.
  # The map compiles in milliseconds and a hash lookup matches or
  # beats the long guard chains at these set sizes.
  @doc false
  def generate_validity_checks(type, validity_data) do
    quote bind_quoted: [type: type, validity_data: Macro.escape(validity_data)] do
      # The validity data is embedded at compile time, so an ETF
      # regeneration must trigger recompilation of this module.
      @external_resource Application.app_dir(
                           :localize,
                           "priv/localize/validity/validity_#{type}.etf"
                         )

      @validity_status_map Localize.Validity.status_map(validity_data)

      defp valid(code) do
        case @validity_status_map do
          %{^code => status} -> {:ok, code, status}
          _no_match -> {:error, code}
        end
      end
    end
  end

  @doc false
  def status_map(validity_data) do
    for {status, codes} <- validity_data,
        code <- expand_codes(codes),
        reduce: %{} do
      acc -> Map.put_new(acc, code, status)
    end
  end

  @doc false
  def expand_codes(codes) do
    {code_ranges, simple_codes} = partition(codes)
    expanded = for range <- code_ranges, range != [], do: expand_range(range)
    simple_codes ++ List.flatten(expanded)
  end

  @doc false
  def partition(list) do
    Enum.reduce(list, {[], []}, fn elem, {ranges, simple} ->
      if String.contains?(elem, "~") do
        {[elem | ranges], simple}
      else
        {ranges, [elem | simple]}
      end
    end)
  end

  @doc false
  def range_from(code_range) do
    [left, range_end] = String.split(code_range, "~")
    {base, range_start} = String.split_at(left, -1)
    <<range_start::utf8>> = range_start
    <<range_end::utf8>> = range_end
    {base, range_start, range_end}
  end

  # Only used for testing
  @doc false
  def all_valid(type) do
    validity_data = Localize.SupplementalData.validity(type)

    for {_status, codes} <- validity_data do
      {code_ranges, simple_codes} = partition(codes)
      range_check = for range <- code_ranges, range != [], do: expand_range(range)
      simple_codes ++ range_check
    end
    |> List.flatten()
  end

  # Expands a code range like "aa~c" into the list of codes it covers.
  defp expand_range(range) do
    {base, range_start, range_end} = range_from(range)

    for char <- range_start..range_end do
      base <> <<char::utf8>>
    end
  end

  # Returns a list of known data that omits
  # valid (per the spec) but shouldn't be used
  # in general practise

  @omit_status [:deprecated, :reserved, :special, :unknown, :private_use]

  @doc false
  def known(type) do
    validity_data = Localize.SupplementalData.validity(type)

    for {status, codes} <- validity_data, status not in @omit_status do
      {code_ranges, simple_codes} = partition(codes)
      range_check = for range <- code_ranges, range != [], do: expand_range(range)
      simple_codes ++ range_check
    end
    |> List.flatten()
  end
end
