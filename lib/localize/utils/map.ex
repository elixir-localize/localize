defmodule Localize.Utils.Map do
  # Functions for transforming maps, keys and values.
  #
  # This module provides recursive map traversal and transformation utilities
  # including key/value type conversion (atomize, stringify, integerize, floatize),
  # deep merging, key renaming, and `camelCase` to `snake_case` conversion.
  #
  # The primary public API includes:
  #
  # * `deep_map/3` - Recursively traverse and transform a map.
  #
  # * `atomize_keys/2` and `atomize_values/2` - Convert string keys/values to atoms.
  #
  # * `stringify_keys/2` and `stringify_values/2` - Convert atom keys/values to strings.
  #
  # * `integerize_keys/2` and `integerize_values/2` - Convert string keys/values to integers.
  #
  # * `floatize_keys/2` and `floatize_values/2` - Convert string keys/values to floats.
  #
  # * `underscore_keys/2` - Convert camelCase string keys to snake_case.
  #
  # * `rename_keys/4` - Rename specific map keys.
  #
  # * `deep_merge/3` - Deep merge two maps.
  #
  # * `merge_map_list/2` - Deep merge a list of maps.
  #
  # * `delete_in/2` - Delete map members by key list.
  #
  # * `invert/2` - Invert a map's keys and values.
  #
  # * `underscore/1` - Convert a camelCase string to snake_case.
  #
  @moduledoc false

  alias Localize.Utils.Helpers

  @doc """
  Returns an argument unchanged.

  Useful when a `noop` function is required.

  ### Returns

  * The argument unchanged.

  ### Examples

      iex> Localize.Utils.Map.identity(:anything)
      :anything

  """
  def identity(x), do: x

  @default_deep_map_options [
    level: 1..1_000_000,
    filter: [],
    reject: [],
    skip: [],
    only: [],
    except: []
  ]
  @starting_level 1
  @max_level 1_000_000

  @doc """
  Recursively traverse a map and invoke a function
  that transforms the map for each key/value pair.

  ### Arguments

  * `map` is any `t:map/0`.

  * `function` is a `1-arity` function or function reference that
    is called for each key/value pair of the provided map. It can
    also be a 2-tuple of the form `{key_function, value_function}`.

    * In the case where `function` is a single function it will be
      called with the 2-tuple argument `{key, value}`.

    * In the case where function is of the form `{key_function, value_function}`
      the `key_function` will be called with the argument `key` and the value
      function will be called with the argument `value`.

  * `options` is a keyword list of options. The default is
    `#{inspect(@default_deep_map_options)}`.

  ### Options

  * `:level` indicates the starting (and optionally ending) levels of
    the map at which the `function` is executed. This can
    be an integer representing one `level` or a range
    indicating a range of levels. The default is `1..#{@max_level}`.

  * `:only` is a term or list of terms or a `check function`. If it is a term
    or list of terms, the `function` is only called if the `key` of the
    map is equal to the term or in the list of terms. If `:only` is a
    `check function` then the `check function` is passed the `{k, v}` of
    the current branch in the `map`. It is expected to return a `truthy`
    value that if `true` signals that the argument `function` will be executed.

  * `:except` is a term or list of terms or a `check function`. If it is a term
    or list of terms, the `function` is only called if the `key` of the
    map is not equal to the term or not in the list of terms. If `:except` is a
    `check function` then the `check function` is passed the `{k, v}` of
    the current branch in the `map`. It is expected to return a `truthy`
    value that if `true` signals that the argument `function` will not be executed.

  * `:filter` is a term or list of terms or a `check function`. If the
    `key` currently being processed equals the term (or is in the list of
    terms, or the `check_function` returns a truthy value) then this branch
    of the map is processed by `function` and its output is included in the result.

  * `:reject` is a term or list of terms or a `check function`. If the
    `key` currently being processed equals the term (or is in the list of
    terms, or the `check_function` returns a truthy value) then this branch
    of the map is omitted from the mapped output.

  * `:skip` is a term or list of terms or a `check function`. If the
    `key` currently being processed equals the term (or is in the list of
    terms, or the `check_function` returns a truthy value) then this branch
    of the map is *not* processed by `function` but it is included in
    the mapped result.

  ### Notes

  * `:only` and `:except` operate on individual keys whereas `:filter`
    and `:reject` operate on *entire branches* of a map.

  * If both the options `:only` and `:except` are provided then the `function`
    is called only when a `term` meets both criteria. That means that `:except`
    has priority over `:only`.

  * If both the options `:filter` and `:reject` are provided then `:reject`
    has priority over `:filter`.

  ### Returns

  * The `map` transformed by the recursive application of `function`.

  ### Examples

      iex> map = %{a: :a, b: %{c: :c}}
      iex> fun = fn
      ...>   {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      ...>   other -> other
      ...> end
      iex> Localize.Utils.Map.deep_map map, fun
      %{"a" => :a, "b" => %{"c" => :c}}
      iex> map = %{a: :a, b: %{c: :c}}
      iex> Localize.Utils.Map.deep_map map, fun, only: :c
      %{a: :a, b: %{"c" => :c}}
      iex> Localize.Utils.Map.deep_map map, fun, except: [:a, :b]
      %{a: :a, b: %{"c" => :c}}
      iex> Localize.Utils.Map.deep_map map, fun, level: 2
      %{a: :a, b: %{"c" => :c}}

  """
  @spec deep_map(
          map() | list(),
          function :: function() | {function(), function()},
          options :: list()
        ) ::
          map() | list()

  def deep_map(map, function, options \\ @default_deep_map_options)

  # Don't deep map structs since they have atom keys anyway and they
  # also don't support enumerable
  def deep_map(%_struct{} = map, _function, _options) when is_map(map) do
    map
  end

  def deep_map(map_or_list, function, options)
      when (is_map(map_or_list) or is_list(map_or_list)) and is_list(options) do
    options = validate_options(function, options)
    deep_map(map_or_list, function, options, @starting_level)
  end

  defp deep_map(nil, _fun, _options, _level) do
    nil
  end

  # If the level is greater than the range
  # just return the map or list
  defp deep_map(map_or_list, _function, %{level: %{last: last}}, level) when level > last do
    map_or_list
  end

  # If the level is less than the range then keep recursing
  # without executing the function
  defp deep_map(map, function, %{level: %{first: first}} = options, level)
       when is_map(map) and level < first do
    Enum.map(map, fn
      {k, v} when is_map(v) or is_list(v) ->
        {k, deep_map(v, function, options, level + 1)}

      {k, v} ->
        {k, v}
    end)
    |> Map.new()
  end

  # Here we are in range so we conditionally execute the function
  # if the options for `:only` and `:except` are matched.
  # Traversal branches on process_type outcome x value shape (nested
  # vs leaf) — five outcomes for each of the two shapes.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp deep_map(map, function, options, level) when is_map(map) and is_function(function) do
    Enum.reduce(map, [], fn
      {k, v}, acc when is_map(v) or is_list(v) ->
        case process_type({k, v}, options) do
          :continue ->
            v = deep_map(v, function, Map.put(options, :filtering, true), level + 1)
            [{k, v} | acc]

          :process ->
            v = deep_map(v, function, Map.put(options, :filtering, true), level + 1)
            [function.({k, v}) | acc]

          :except ->
            v = deep_map(v, function, options, level + 1)
            [{k, v} | acc]

          :skip ->
            [function.({k, v}) | acc]

          :reject ->
            acc
        end

      {k, v}, acc ->
        case process_type({k, v}, options) do
          :continue ->
            [{k, v} | acc]

          :process ->
            [function.({k, v}) | acc]

          :except ->
            [{k, v} | acc]

          :skip ->
            [function.({k, v}) | acc]

          :reject ->
            acc
        end
    end)
    |> Map.new()
  end

  # Same process_type-outcome x value-shape branching for the
  # {key_function, value_function} pair form.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp deep_map(map, {key_function, value_function}, options, level) when is_map(map) do
    Enum.reduce(map, [], fn
      {k, v}, acc when is_map(v) or is_list(v) ->
        case process_type({k, v}, options) do
          :continue ->
            v =
              deep_map(
                v,
                {key_function, value_function},
                Map.put(options, :filtering, true),
                level + 1
              )

            [{k, v} | acc]

          :process ->
            v =
              deep_map(
                v,
                {key_function, value_function},
                Map.put(options, :filtering, true),
                level + 1
              )

            [{key_function.(k), value_function.(v)} | acc]

          :except ->
            v = deep_map(v, {key_function, value_function}, options, level + 1)
            [{k, v} | acc]

          :skip ->
            [{key_function.(k), v} | acc]

          :reject ->
            acc
        end

      {k, v}, acc ->
        case process_type({k, v}, options) do
          :continue ->
            [{k, v} | acc]

          :process ->
            [{key_function.(k), value_function.(v)} | acc]

          :except ->
            [{k, v} | acc]

          :skip ->
            [{key_function.(k), v} | acc]

          :reject ->
            acc
        end
    end)
    |> Map.new()
  end

  defp deep_map([], _function, _options, _level) do
    []
  end

  defp deep_map([head | rest], function, options, level) do
    case process_type(head, options) do
      :continue ->
        [head | deep_map(rest, function, Map.put(options, :filtering, true), level + 1)]

      :process ->
        [
          deep_map(head, function, Map.put(options, :filtering, true), level + 1)
          | deep_map(rest, function, options, level + 1)
        ]

      :except ->
        [
          deep_map(head, function, options, level + 1)
          | deep_map(rest, function, options, level + 1)
        ]

      :skip ->
        [head | deep_map(rest, function, options, level + 1)]

      :reject ->
        deep_map(rest, function, options, level + 1)
    end
  end

  defp deep_map(value, function, options, _level) when is_function(function) do
    case process_type(value, options) do
      :continue ->
        value

      :process ->
        function.(value)

      :except ->
        value

      :skip ->
        value

      :reject ->
        nil
    end
  end

  defp deep_map(value, {_key_function, value_function}, options, _level) do
    case process_type(value, options) do
      :continue ->
        value

      :process ->
        value_function.(value)

      :skip ->
        value

      :reject ->
        nil
    end
  end

  @doc """
  Transforms a `map`'s `String.t` keys to `atom()` keys.

  ### Arguments

  * `map` is any `t:map/0`.

  * `options` is a keyword list of options passed
    to `deep_map/3`. One additional option applies
    to this function directly:

    * `:only_existing` which is set to `true` will
      only convert the binary value to an atom if the atom
      already exists. The default is `false`.

  ### Returns

  * A map with string keys converted to atom keys.

  ### Examples

      iex> Localize.Utils.Map.atomize_keys %{"a" => %{"b" => %{1 => "c"}}}
      %{a: %{b: %{1 => "c"}}}

  """
  @default_atomize_options [only_existing: false]
  def atomize_keys(map, options \\ [])

  def atomize_keys(map, options) when is_map(map) or is_list(map) do
    options = @default_atomize_options ++ options
    map_options = Map.new(options)

    deep_map(map, &atomize_key(&1, map_options), options)
  end

  def atomize_keys({k, value}, options) when is_map(value) or is_list(value) do
    options = @default_atomize_options ++ options
    map_options = Map.new(options)

    {atomize_key(k, map_options), deep_map(value, &atomize_key(&1, map_options), options)}
  end

  def atomize_keys(other, _options) do
    other
  end

  @doc """
  Transforms a `map`'s `String.t` values to `atom()` values.

  ### Arguments

  * `map` is any `t:map/0`.

  * `options` is a keyword list of options passed
    to `deep_map/3`. One additional option applies
    to this function directly:

    * `:only_existing` which is set to `true` will
      only convert the binary value to an atom if the atom
      already exists. The default is `false`.

  ### Returns

  * A map with string values converted to atom values.

  ### Examples

      iex> Localize.Utils.Map.atomize_values %{"a" => %{"b" => %{1 => "c"}}}
      %{"a" => %{"b" => %{1 => :c}}}

  """
  def atomize_values(map, options \\ [only_existing: false])

  def atomize_values(map, options) when is_map(map) or is_list(map) do
    options = @default_atomize_options ++ options
    map_options = Map.new(options)

    deep_map(map, &atomize_value(&1, map_options), options)
  end

  def atomize_values({k, value}, options) when is_map(value) or is_list(value) do
    options = @default_atomize_options ++ options
    map_options = Map.new(options)

    {k, deep_map(value, &atomize_value(&1, map_options), options)}
  end

  def atomize_values(other, _options) do
    other
  end

  @doc """
  Transforms a `map`'s `String.t` keys to `Integer.t` keys.

  ### Arguments

  * `map` is any `t:map/0`.

  * `options` is a keyword list of options passed
    to `deep_map/3`.

  The map key is converted to an `integer` from
  either an `atom` or `String.t` only when the
  key is comprised of `integer` digits.

  Keys which cannot be converted to an `integer`
  are returned unchanged.

  ### Returns

  * A map with string keys converted to integer keys where possible.

  ### Examples

      iex> Localize.Utils.Map.integerize_keys %{a: %{"1" => "value"}}
      %{a: %{1 => "value"}}

  """
  def integerize_keys(map, options \\ [])

  def integerize_keys(map, options) when is_map(map) or is_list(map) do
    deep_map(map, &integerize_key/1, options)
  end

  def integerize_keys({k, value}, options) when is_map(value) or is_list(value) do
    {integerize_key(k), deep_map(value, &integerize_key/1, options)}
  end

  @doc """
  Transforms a `map`'s `String.t` values to `Integer.t` values.

  ### Arguments

  * `map` is any `t:map/0`.

  * `options` is a keyword list of options passed
    to `deep_map/3`.

  The map value is converted to an `integer` from
  either an `atom` or `String.t` only when the
  value is comprised of `integer` digits.

  Values which cannot be converted to an integer
  are returned unchanged.

  ### Returns

  * A map with string values converted to integer values where possible.

  ### Examples

      iex> Localize.Utils.Map.integerize_values %{a: %{b: "1"}}
      %{a: %{b: 1}}

  """
  def integerize_values(map, options \\ []) do
    deep_map(map, &integerize_value/1, options)
  end

  @doc """
  Transforms a `map`'s `String.t` keys to `Float.t` keys.

  ### Arguments

  * `map` is any `t:map/0`.

  * `options` is a keyword list of options passed
    to `deep_map/3`.

  The map key is converted to a `float` from
  a `String.t` only when the key is comprised of
  a valid float form.

  Keys which cannot be converted to a `float`
  are returned unchanged.

  ### Returns

  * A map with string keys converted to float keys where possible.

  ### Examples

      iex> Localize.Utils.Map.floatize_keys %{a: %{"1.0" => "value"}}
      %{a: %{1.0 => "value"}}

      iex> Localize.Utils.Map.floatize_keys %{a: %{"1" => "value"}}
      %{a: %{1.0 => "value"}}

  """
  def floatize_keys(map, options \\ [])

  def floatize_keys(map, options) when is_map(map) or is_list(map) do
    deep_map(map, &floatize_key/1, options)
  end

  def floatize_keys({k, value}, options) when is_map(value) or is_list(value) do
    {floatize_key(k), deep_map(value, &floatize_key/1, options)}
  end

  @doc """
  Transforms a `map`'s `String.t` values to `Float.t` values.

  ### Arguments

  * `map` is any `t:map/0`.

  * `options` is a keyword list of options passed
    to `deep_map/3`.

  The map value is converted to a `float` from
  a `String.t` only when the
  value is comprised of a valid float form.

  Values which cannot be converted to a `float`
  are returned unchanged.

  ### Returns

  * A map with string values converted to float values where possible.

  ### Examples

      iex> Localize.Utils.Map.floatize_values %{a: %{b: "1.0"}}
      %{a: %{b: 1.0}}

      iex> Localize.Utils.Map.floatize_values %{a: %{b: "1"}}
      %{a: %{b: 1.0}}

  """
  def floatize_values(map, options \\ []) do
    deep_map(map, &floatize_value/1, options)
  end

  @doc """
  Transforms a `map`'s `atom()` keys to `String.t` keys.

  ### Arguments

  * `map` is any `t:map/0`.

  * `options` is a keyword list of options passed
    to `deep_map/3`.

  ### Returns

  * A map with atom keys converted to string keys.

  ### Examples

      iex> Localize.Utils.Map.stringify_keys %{a: %{"1" => "value"}}
      %{"a" => %{"1" => "value"}}

  """
  def stringify_keys(map, options \\ [])

  def stringify_keys(map, options) when is_map(map) or is_list(map) do
    deep_map(map, &stringify_key/1, options)
  end

  def stringify_keys({k, value}, options) when is_map(value) or is_list(value) do
    {stringify_key(k), deep_map(value, &stringify_key/1, options)}
  end

  @doc """
  Transforms a `map`'s `atom()` values to `String.t` values.

  ### Arguments

  * `map` is any `t:map/0`.

  * `options` is a keyword list of options passed
    to `deep_map/3`.

  ### Returns

  * A map with atom values converted to string values.

  ### Examples

      iex> Localize.Utils.Map.stringify_values %{a: %{"1" => :value}}
      %{a: %{"1" => "value"}}

  """
  def stringify_values(map, options \\ []) do
    deep_map(map, &stringify_value/1, options)
  end

  @doc """
  Convert map `String.t` keys from `camelCase` to `snake_case`.

  ### Arguments

  * `map` is any `t:map/0`.

  * `options` is a keyword list of options passed
    to `deep_map/3`.

  ### Returns

  * A map with camelCase string keys converted to snake_case.

  ### Examples

      iex> Localize.Utils.Map.underscore_keys %{"a" => %{"thisOne" => "value"}}
      %{"a" => %{"this_one" => "value"}}

  """
  def underscore_keys(map, options \\ [])

  def underscore_keys(nil, _options) do
    nil
  end

  def underscore_keys(map, options) when is_map(map) do
    deep_map(map, &underscore_key/1, options)
  end

  def underscore_keys({k, value}, options) when is_map(value) or is_list(value) do
    {underscore_key(k), deep_map(value, &underscore_key/1, options)}
  end

  @doc """
  Rename map keys from `from` to `to`.

  ### Arguments

  * `map` is any `t:map/0`.

  * `from` is any value map key.

  * `to` is any valid map key.

  * `options` is a keyword list of options passed
    to `deep_map/3`.

  ### Returns

  * A map with keys matching `from` renamed to `to`.

  ### Examples

      iex> Localize.Utils.Map.rename_keys %{"a" => %{"this_one" => "value"}}, "this_one", "that_one"
      %{"a" => %{"that_one" => "value"}}

  """
  def rename_keys(map, from, to, options \\ []) when is_map(map) or is_list(map) do
    renamer = fn
      {^from, v} -> {to, v}
      other -> other
    end

    deep_map(map, renamer, options)
  end

  @doc """
  Convert a camelCase string or atom to snake_case.

  This is the code of `Macro.underscore/1` with modifications.
  The change is to cater for strings in the format `This_That`
  which in `Macro.underscore/1` gets formatted as `this__that`
  (note the double underscore) when we actually want `this_that`.

  ### Arguments

  * `string` is a `String.t` or `atom()` to be transformed.

  ### Returns

  * A snake_case `String.t`.

  ### Examples

      iex> Localize.Utils.Map.underscore "thisThat"
      "this_that"

      iex> Localize.Utils.Map.underscore "This_That"
      "this_that"

  """
  @spec underscore(string :: String.t() | atom()) :: String.t()
  def underscore(<<h, t::binary>>) do
    <<to_lower_char(h)>> <> do_underscore(t, h)
  end

  def underscore(other) do
    other
  end

  @doc """
  Removes any leading underscores from `map` `String.t` keys.

  ### Arguments

  * `map` is any `t:map/0`.

  * `options` is a keyword list of options passed
    to `deep_map/3`.

  ### Returns

  * A map with leading underscores removed from string keys.

  ### Examples

      iex> Localize.Utils.Map.remove_leading_underscores %{"a" => %{"_b" => "b"}}
      %{"a" => %{"b" => "b"}}

  """
  def remove_leading_underscores(map, options \\ []) do
    remover = fn
      {k, v} when is_binary(k) -> {String.trim_leading(k, "_"), v}
      other -> other
    end

    deep_map(map, remover, options)
  end

  @doc """
  Returns the result of deep merging a list of maps.

  ### Arguments

  * `list` is a list of maps to be merged.

  * `resolver` is a 3-arity function used to resolve merge conflicts.
    The default resolver prefers the right-side value and recursively
    merges nested maps.

  ### Returns

  * A single map that is the result of deep merging all maps in the list.

  ### Examples

      iex> Localize.Utils.Map.merge_map_list [%{a: "a", b: "b"}, %{c: "c", d: "d"}]
      %{a: "a", b: "b", c: "c", d: "d"}

  """
  def merge_map_list(list, resolver \\ &standard_deep_resolver/3)

  def merge_map_list([h | []], _resolver) do
    h
  end

  def merge_map_list([h | t], resolver) do
    deep_merge(h, merge_map_list(t, resolver), resolver)
  end

  def merge_map_list([], _resolver) do
    []
  end

  @doc """
  Deep merge two maps.

  ### Arguments

  * `left` is any `t:map/0`.

  * `right` is any `t:map/0`.

  * `resolver` is a 3-arity function used to resolve merge conflicts.
    The default resolver prefers the right-side value and recursively
    merges nested maps.

  ### Returns

  * A single map that is the deep merge of `left` and `right`.

  ### Examples

      iex> Localize.Utils.Map.deep_merge %{a: "a", b: "b"}, %{c: "c", d: "d"}
      %{a: "a", b: "b", c: "c", d: "d"}

      iex> Localize.Utils.Map.deep_merge %{a: "a", b: "b"}, %{c: "c", d: "d", a: "aa"}
      %{a: "aa", b: "b", c: "c", d: "d"}

  """
  def deep_merge(left, right, resolver \\ &standard_deep_resolver/3)
      when is_map(left) and is_map(right) do
    Map.merge(left, right, resolver)
  end

  # Key exists in both maps, and both values are maps as well.
  # These can be merged recursively.
  defp standard_deep_resolver(_key, left, right) when is_map(left) and is_map(right) do
    deep_merge(left, right, &standard_deep_resolver/3)
  end

  # Key exists in both maps, but at least one of the values is
  # NOT a map. We fall back to standard merge behavior, preferring
  # the value on the right.
  defp standard_deep_resolver(_key, _left, right) do
    right
  end

  @doc false
  def combine_list_resolver(_key, left, right) when is_list(left) and is_list(right) do
    left ++ right
  end

  @doc """
  Delete all members of a map that have a key in the list of keys.

  ### Arguments

  * `map` is any `t:map/0` or keyword list.

  * `keys` is a list of keys to delete.

  ### Returns

  * The map with all matching keys removed at any depth.

  ### Examples

      iex> Localize.Utils.Map.delete_in %{a: "a", b: "b"}, [:a]
      %{b: "b"}

  """
  def delete_in(%{} = map, keys) when is_list(keys) do
    Enum.reject(map, fn {k, _v} -> k in keys end)
    |> Enum.map(fn {k, v} -> {k, delete_in(v, keys)} end)
    |> Map.new()
  end

  def delete_in(map, keys) when is_list(map) and is_binary(keys) do
    delete_in(map, [keys])
  end

  def delete_in(map, keys) when is_list(map) do
    Enum.reject(map, fn {k, _v} -> k in keys end)
    |> Enum.map(fn {k, v} -> {k, delete_in(v, keys)} end)
  end

  def delete_in(%{} = map, keys) when is_binary(keys) do
    delete_in(map, [keys])
  end

  def delete_in(other, _keys) do
    other
  end

  @doc false
  def from_keyword([] = list) do
    Map.new(list)
  end

  @doc false
  def from_keyword([{key, _value} | _rest] = keyword_list) when is_atom(key) do
    Map.new(keyword_list)
  end

  @doc """
  Extract strings from a map or list.

  Recursively process the map or list
  and extract string values from maps
  and string elements from lists.

  ### Arguments

  * `map_or_list` is any `t:map/0` or list.

  * `options` is a keyword list of options (currently unused).

  ### Returns

  * A flattened list of all string values found in the map or list.

  """
  def extract_strings(map_or_list, options \\ [])

  def extract_strings([], _options) do
    []
  end

  def extract_strings(map, _options) when is_map(map) do
    Enum.reduce(map, [], fn
      {_k, v}, acc when is_binary(v) -> [v | acc]
      {_k, v}, acc when is_map(v) -> [extract_strings(v) | acc]
      {_k, v}, acc when is_list(v) -> [extract_strings(v) | acc]
      _other, acc -> acc
    end)
    |> List.flatten()
  end

  def extract_strings(list, _options) when is_list(list) do
    Enum.reduce(list, [], fn
      v, acc when is_binary(v) -> [v | acc]
      v, acc when is_map(v) -> [extract_strings(v) | acc]
      v, acc when is_list(v) -> [extract_strings(v) | acc]
      _other, acc -> acc
    end)
    |> List.flatten()
  end

  @doc """
  Prune a potentially deeply nested map of some of its branches.

  ### Arguments

  * `map` is any `t:map/0`.

  * `fun` is a 1-arity function. Branches for which the function
    returns a truthy value are removed from the map.

  ### Returns

  * The map with matching branches pruned.

  """
  def prune(map, fun) when is_map(map) and is_function(fun, 1) do
    deep_map(map, & &1, reject: fun)
  end

  @doc """
  Invert a map.

  Requires that the map is a simple map of
  keys and a list of values or a single
  non-map value.

  ### Arguments

  * `map` is any `t:map/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:duplicates` which determines how duplicate values
    are handled:

    * `nil` or `false` which is the default and means only
      one value is kept. `Map.new/1` is used meaning the
      selected value is non-deterministic.

    * `:keep` meaning duplicate values are returned in a list.

    * `:shortest` means the shortest duplicate is kept.
      This operates on string or atom values.

    * `:longest` means the longest duplicate is kept.
      This operates on string or atom values.

  ### Returns

  * A map with keys and values swapped.

  """
  def invert(map, options \\ [])

  def invert(map, options) when is_map(map) do
    map
    |> Enum.map(fn
      {k, v} when is_list(v) -> Enum.map(v, fn vv -> {vv, k} end)
      {k, v} when not is_map(v) -> {v, k}
    end)
    |> List.flatten()
    |> process_duplicates(options[:duplicates])
  end

  defp process_duplicates(list, keep) when is_nil(keep) or keep == false do
    Map.new(list)
  end

  defp process_duplicates(list, :keep) do
    list
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp process_duplicates(list, :shortest) do
    list
    |> process_duplicates(:keep)
    |> Enum.map(fn {k, v} -> {k, shortest(v)} end)
    |> Map.new()
  end

  defp process_duplicates(list, :longest) do
    list
    |> process_duplicates(:keep)
    |> Enum.map(fn {k, v} -> {k, longest(v)} end)
    |> Map.new()
  end

  defp shortest(list) when is_list(list) do
    Enum.min_by(list, &len/1)
  end

  defp longest(list) when is_list(list) do
    Enum.max_by(list, &len/1)
  end

  defp len(e) when is_binary(e) do
    String.length(e)
  end

  defp len(e) when is_atom(e) do
    e
    |> Atom.to_string()
    |> len()
  end

  #
  # Helpers
  #

  defp validate_options(function, options) when is_function(function) do
    validate_options(options)
  end

  defp validate_options({key_function, value_function}, options)
       when is_function(key_function) and is_function(value_function) do
    validate_options(options)
  end

  defp validate_options(function, _options) do
    raise Localize.InvalidValueError.exception(
            value: function,
            expected: :function_or_key_value_function_pair
          )
  end

  defp validate_options(options) do
    @default_deep_map_options
    |> Keyword.merge(options)
    |> Map.new()
    |> Map.update!(:level, fn
      level when is_integer(level) ->
        level..level

      %Range{} = level ->
        level

      other ->
        raise Localize.InvalidValueError.exception(
                value: other,
                expected: :integer_or_range,
                context: :level
              )
    end)
  end

  defp atomize_key({k, v}, %{only_existing: true}) when is_binary(k) do
    {Helpers.existing_atom(k) || k, v}
  end

  defp atomize_key({k, v}, %{only_existing: false}) when is_binary(k) do
    {String.to_atom(k), v}
  end

  defp atomize_key(other, _options) do
    other
  end

  defp atomize_value({k, v}, %{only_existing: true}) when is_binary(v) do
    {k, Helpers.existing_atom(v) || v}
  end

  defp atomize_value({k, v}, %{only_existing: false}) when is_binary(v) do
    {k, String.to_atom(v)}
  end

  defp atomize_value(v, %{only_existing: false}) when is_binary(v) do
    String.to_atom(v)
  end

  defp atomize_value(other, _options) do
    other
  end

  defp integerize_key({k, v}) when is_binary(k) do
    case Integer.parse(k) do
      {integer, ""} -> {integer, v}
      _other -> {k, v}
    end
  end

  defp integerize_key(other) do
    other
  end

  defp integerize_value({k, v}) when is_binary(v) do
    case Integer.parse(v) do
      {integer, ""} -> {k, integer}
      _other -> {k, v}
    end
  end

  defp integerize_value(other) do
    other
  end

  defp floatize_key({k, v}) when is_binary(k) do
    case Float.parse(k) do
      {float, ""} -> {float, v}
      _other -> {k, v}
    end
  end

  defp floatize_key(other) do
    other
  end

  defp floatize_value({k, v}) when is_binary(v) do
    case Float.parse(v) do
      {float, ""} -> {k, float}
      _other -> {k, v}
    end
  end

  defp floatize_value(other) do
    other
  end

  defp stringify_key({k, v}) when is_atom(k), do: {Atom.to_string(k), v}
  defp stringify_key(other), do: other

  defp stringify_value({k, v}) when is_atom(v), do: {k, Atom.to_string(v)}
  defp stringify_value(other) when is_atom(other), do: Atom.to_string(other)
  defp stringify_value(other), do: other

  defp underscore_key({k, v}) when is_binary(k), do: {underscore(k), v}
  defp underscore_key(other), do: other

  # process_type/2 determines whether the calling function
  # should apply to a given value
  @doc false
  def process_type(x, options) do
    filter? = filter?(x, options)
    reject? = reject?(x, options)

    cond do
      reject? -> :reject
      skip?(x, options) -> :skip
      filter? && only?(x, options) && !except?(x, options) -> :process
      filter? -> :continue
      true -> :except
    end
  end

  # Keep this branch but don't process it
  defp skip?(x, %{skip: skip}) when is_function(skip) do
    skip.(x)
  end

  defp skip?({k, _v}, %{skip: skip}) when is_list(skip) do
    k in skip
  end

  defp skip?({k, _v}, %{skip: skip}) do
    k == skip
  end

  defp skip?(k, %{skip: skip}) when is_list(skip) do
    k in skip
  end

  defp skip?(k, %{skip: skip}) do
    k == skip
  end

  # Keep this branch in the result
  defp filter?(x, %{filter: filter}) when is_function(filter) do
    filter.(x)
  end

  defp filter?(_x, %{filtering: true}) do
    true
  end

  defp filter?(_x, %{filter: []}) do
    true
  end

  defp filter?({k, _v}, %{filter: filter}) when is_list(filter) do
    k in filter
  end

  defp filter?({k, _v}, %{filter: filter}) do
    k == filter
  end

  defp filter?(k, %{filter: filter}) when is_list(filter) do
    k in filter
  end

  defp filter?(k, %{filter: filter}) do
    k == filter
  end

  # Don't include this branch in the result
  defp reject?(x, %{reject: reject}) when is_function(reject) do
    reject.(x)
  end

  defp reject?({k, _v}, %{reject: reject}) when is_list(reject) do
    k in reject
  end

  defp reject?({k, _v}, %{reject: reject}) do
    k == reject
  end

  defp reject?(k, %{reject: reject}) when is_list(reject) do
    k in reject
  end

  defp reject?(k, %{reject: reject}) do
    k == reject
  end

  # Process this item
  defp only?(x, %{only: only}) when is_function(only) do
    only.(x)
  end

  defp only?(_x, %{only: []}) do
    true
  end

  defp only?({k, _v}, %{only: only}) when is_list(only) do
    k in only
  end

  defp only?({k, _v}, %{only: only}) do
    k == only
  end

  defp only?(k, %{only: only}) when is_list(only) do
    k in only
  end

  defp only?(k, %{only: only}) do
    k == only
  end

  # Don't process this item
  defp except?(x, %{except: except}) when is_function(except) do
    except.(x)
  end

  defp except?({k, _v}, %{except: except}) when is_list(except) do
    k in except
  end

  defp except?({k, _v}, %{except: except}) do
    k == except
  end

  defp except?(k, %{except: except}) when is_list(except) do
    k in except
  end

  defp except?(k, %{except: except}) do
    k == except
  end

  # underscore/1 helpers
  # h is upper case, next char is not uppercase, or a _ or .  => and prev != _
  defp do_underscore(<<h, t, rest::binary>>, prev)
       when h >= ?A and h <= ?Z and not (t >= ?A and t <= ?Z) and t != ?. and t != ?_ and t != ?- and
              prev != ?_ do
    <<?_, to_lower_char(h), t>> <> do_underscore(rest, t)
  end

  # h is uppercase, previous was not uppercase or _
  defp do_underscore(<<h, t::binary>>, prev)
       when h >= ?A and h <= ?Z and not (prev >= ?A and prev <= ?Z) and prev != ?_ do
    <<?_, to_lower_char(h)>> <> do_underscore(t, h)
  end

  # h is dash "-" -> replace with underscore "_"
  defp do_underscore(<<?-, t::binary>>, _) do
    <<?_>> <> underscore(t)
  end

  # h is .
  defp do_underscore(<<?., t::binary>>, _) do
    <<?/>> <> underscore(t)
  end

  # Any other char
  defp do_underscore(<<h, t::binary>>, _) do
    <<to_lower_char(h)>> <> do_underscore(t, h)
  end

  defp do_underscore(<<>>, _) do
    <<>>
  end

  defp to_lower_char(char) when char == ?-, do: ?_
  defp to_lower_char(char) when char >= ?A and char <= ?Z, do: char + 32
  defp to_lower_char(char), do: char
end
