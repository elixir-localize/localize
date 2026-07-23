defmodule Localize.Substitution do
  # Compiles substitution templates of the form `"{0} something {1}"`
  # into token lists for efficient parameter substitution at runtime.
  #
  # Templates are parsed once into a list of string literals and
  # integer indices. At runtime, values are substituted for the
  # integer indices to produce the final output.
  #
  @moduledoc false

  @doc """
  Parses a substitution template into a list of tokens.

  ### Arguments

  * `template` is a binary string that may include parameter
    markers like `{0}`, `{1}`, etc.

  ### Returns

  * A list of tokens where substitution markers become integers
    and literal text remains as strings.

  ### Examples

      iex> Localize.Substitution.parse("{0}, {1}")
      [0, ", ", 1]

      iex> Localize.Substitution.parse("{0} something {1} else {2}")
      [0, " something ", 1, " else ", 2]

      iex> Localize.Substitution.parse("")
      []

  """
  @spec parse(String.t()) :: [String.t() | integer()]
  def parse("") do
    []
  end

  def parse(template) when is_binary(template) do
    template
    |> String.split(~r/{[0-9]}/, include_captures: true, trim: true)
    |> Enum.map(&item_from_token/1)
  end

  @doc """
  Substitutes values into a pre-parsed template token list.

  ### Arguments

  * `values` is a value or list of values to substitute into
    the template.

  * `tokens` is a template token list previously created by
    `parse/1`.

  ### Returns

  * A list with values substituted for integer indices in the
    template.

  ### Examples

      iex> template = Localize.Substitution.parse("{0} and {1}")
      [0, " and ", 1]
      iex> Localize.Substitution.substitute(["a", "b"], template)
      ["a", " and ", "b"]

      iex> Localize.Substitution.substitute("x", [0, "!"])
      ["x", "!"]

  """
  @spec substitute(term() | [term()], [String.t() | integer()]) :: [term()]

  # Single item, single token
  def substitute(item, [0]) do
    [item]
  end

  def substitute([item], [0]) do
    [item]
  end

  # No parameters used — just a literal string
  def substitute([_item], [string]) when is_binary(string) do
    [string]
  end

  def substitute(_item, [string]) when is_binary(string) do
    [string]
  end

  # One parameter: {0}string
  def substitute([item], [0, string]) when is_binary(string) do
    [item, string]
  end

  def substitute(item, [0, string]) when is_binary(string) do
    [item, string]
  end

  # One parameter: string{0}
  def substitute([item], [string, 0]) when is_binary(string) do
    [string, item]
  end

  def substitute(item, [string, 0]) when is_binary(string) do
    [string, item]
  end

  # One parameter: string{0}string
  def substitute(item, [string1, 0, string2])
      when is_binary(string1) and is_binary(string2) do
    [string1, item, string2]
  end

  # Two parameters: {0}{1}
  def substitute([item_0, item_1], [0, 1]) do
    [item_0, item_1]
  end

  # Two parameters: {0}string{1}
  def substitute([item_0, item_1], [0, string, 1]) when is_binary(string) do
    [item_0, string, item_1]
  end

  # Two parameters: {1}string{0}
  def substitute([item_0, item_1], [1, string, 0]) when is_binary(string) do
    [item_1, string, item_0]
  end

  # Two parameters with trailing: {0}string{1}string
  def substitute([item_0, item_1], [0, string1, 1, string2]) do
    [item_0, string1, item_1, string2]
  end

  def substitute([item_0, item_1], [1, string1, 0, string2]) do
    [item_1, string1, item_0, string2]
  end

  # Three parameters: {0}string{1}string{2}
  def substitute([item_0, item_1, item_2], [0, string_1, 1, string_2, 2])
      when is_binary(string_1) and is_binary(string_2) do
    [item_0, string_1, item_1, string_2, item_2]
  end

  @doc """
  Substitutes parts lists into a pre-parsed template token list.

  The parts-aware sibling of `substitute/2`: each integer index in
  the token list is replaced by the parts list at that position, and
  each template literal becomes a part of `literal_type` (default
  `:literal`). The result is a flat parts list.

  ### Arguments

  * `parts_lists` is a list of parts lists, one per template index.

  * `tokens` is a template token list previously created by
    `parse/1`.

  * `literal_type` is the part type used for template literals.

  ### Returns

  * A flat list of `%{type: atom(), value: String.t()}` maps.

  ### Examples

      iex> template = Localize.Substitution.parse("{0}–{1}")
      iex> parts = [[%{type: :integer, value: "3"}], [%{type: :integer, value: "5"}]]
      iex> Localize.Substitution.substitute_parts(parts, template)
      [
        %{type: :integer, value: "3"},
        %{type: :literal, value: "–"},
        %{type: :integer, value: "5"}
      ]

  """
  @spec substitute_parts([[map()]], [String.t() | integer()], atom()) :: [map()]
  def substitute_parts(parts_lists, tokens, literal_type \\ :literal) do
    Enum.flat_map(tokens, fn
      index when is_integer(index) -> Enum.at(parts_lists, index, [])
      literal when is_binary(literal) -> [%{type: literal_type, value: literal}]
    end)
  end

  # ── Private ─────────────────────────────────────────────────

  @digits [?0, ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9]

  defp item_from_token(<<?{, digit, ?}>>) when digit in @digits do
    digit - ?0
  end

  defp item_from_token(string) do
    string
  end
end
