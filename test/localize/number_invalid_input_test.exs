defmodule Localize.NumberInvalidInputTest do
  @moduledoc """
  The public `Localize.Number` functions, and the `Localize.Number.Parser`
  functions they delegate to, given a value or options of the wrong type
  return `{:error, %Localize.InvalidValueError{}}` rather than raising, and
  each bang variant raises the error its non-bang variant returns.

  """

  use ExUnit.Case, async: true

  @not_numbers [:bogus, nil, "12", [1], %{}, {1, 2}]
  @not_keyword_lists [:bogus, nil, [1], %{}, "x"]

  defp outcome(fun) do
    fun.()
  rescue
    exception -> {:raised, exception}
  end

  defp invalid_value?(result), do: match?({:error, %Localize.InvalidValueError{}}, result)

  test "formatting a value that is not a number is an error" do
    failures =
      for value <- @not_numbers,
          {name, fun} <- [
            to_string: fn -> Localize.Number.to_string(value) end,
            to_parts: fn -> Localize.Number.to_parts(value) end,
            to_range_string_start: fn -> Localize.Number.to_range_string(value, 5) end,
            to_range_string_end: fn -> Localize.Number.to_range_string(1, value) end,
            to_range_parts_start: fn -> Localize.Number.to_range_parts(value, 5) end,
            to_range_parts_end: fn -> Localize.Number.to_range_parts(1, value) end,
            to_at_least_string: fn -> Localize.Number.to_at_least_string(value) end,
            to_at_most_string: fn -> Localize.Number.to_at_most_string(value) end,
            to_approximately_string: fn -> Localize.Number.to_approximately_string(value) end,
            to_ratio_string: fn -> Localize.Number.to_ratio_string(value) end
          ],
          result = outcome(fun),
          not invalid_value?(result),
          do: {name, value, result}

    assert failures == []
  end

  test "options that are not a keyword list are an error" do
    failures =
      for options <- @not_keyword_lists,
          {name, fun} <- [
            to_string: fn -> Localize.Number.to_string(1, options) end,
            to_string_decimal: fn -> Localize.Number.to_string(Decimal.new(1), options) end,
            to_parts: fn -> Localize.Number.to_parts(1, options) end,
            to_range_string: fn -> Localize.Number.to_range_string(1, 2, options) end,
            to_range_string_range: fn -> Localize.Number.to_range_string(1..2, options) end,
            to_range_parts: fn -> Localize.Number.to_range_parts(1, 2, options) end,
            to_at_least_string: fn -> Localize.Number.to_at_least_string(1, options) end,
            to_at_most_string: fn -> Localize.Number.to_at_most_string(1, options) end,
            to_approximately_string: fn -> Localize.Number.to_approximately_string(1, options) end,
            to_ratio_string: fn -> Localize.Number.to_ratio_string(0.5, options) end,
            parse: fn -> Localize.Number.parse("1", options) end,
            scan: fn -> Localize.Number.scan("1", options) end,
            resolve_currency: fn -> Localize.Number.resolve_currency("$1", options) end,
            resolve_currencies: fn -> Localize.Number.resolve_currencies(["$1"], options) end,
            resolve_per: fn -> Localize.Number.resolve_per("1%", options) end,
            resolve_pers: fn -> Localize.Number.resolve_pers(["1%"], options) end
          ],
          result = outcome(fun),
          not invalid_value?(result),
          do: {name, options, result}

    assert failures == []
  end

  test "parsing input of the wrong type is an error" do
    strings =
      for value <- [:bogus, nil, 12, %{}, {1, 2}],
          {name, fun} <- [
            parse: fn -> Localize.Number.parse(value) end,
            scan: fn -> Localize.Number.scan(value) end,
            resolve_currency: fn -> Localize.Number.resolve_currency(value) end,
            resolve_per: fn -> Localize.Number.resolve_per(value) end
          ],
          result = outcome(fun),
          not invalid_value?(result),
          do: {name, value, result}

    lists =
      for value <- [:bogus, nil, "1%", 12, %{}],
          {name, fun} <- [
            resolve_currencies: fn -> Localize.Number.resolve_currencies(value) end,
            resolve_pers: fn -> Localize.Number.resolve_pers(value) end
          ],
          result = outcome(fun),
          not invalid_value?(result),
          do: {name, value, result}

    assert strings ++ lists == []
  end

  test "bang variants raise the error their non-bang variant returns" do
    cases = [
      {fn -> Localize.Number.to_string(:bogus) end, fn -> Localize.Number.to_string!(:bogus) end},
      {fn -> Localize.Number.to_parts(1, :bogus) end,
       fn -> Localize.Number.to_parts!(1, :bogus) end},
      {fn -> Localize.Number.to_range_string(1, :bogus) end,
       fn -> Localize.Number.to_range_string!(1, :bogus) end},
      {fn -> Localize.Number.to_range_parts(:bogus, 2) end,
       fn -> Localize.Number.to_range_parts!(:bogus, 2) end},
      {fn -> Localize.Number.to_at_least_string(nil) end,
       fn -> Localize.Number.to_at_least_string!(nil) end},
      {fn -> Localize.Number.to_at_most_string(nil) end,
       fn -> Localize.Number.to_at_most_string!(nil) end},
      {fn -> Localize.Number.to_approximately_string(nil) end,
       fn -> Localize.Number.to_approximately_string!(nil) end},
      {fn -> Localize.Number.to_ratio_string("half") end,
       fn -> Localize.Number.to_ratio_string!("half") end}
    ]

    for {plain, bang} <- cases do
      assert {:error, %{__exception__: true, __struct__: module}} = plain.()
      assert_raise module, bang
    end
  end
end
