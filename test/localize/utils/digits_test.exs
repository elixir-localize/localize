defmodule Localize.Utils.DigitsTest do
  use ExUnit.Case, async: true

  alias Localize.Utils.Digits

  doctest Localize.Utils.Digits

  test "test to_digits(zero)" do
    assert {[0], 1, 1} == Digits.to_digits(0.0)
  end

  test "test to_digits(one)" do
    assert {[1], 1, 1} == Digits.to_digits(1.0)
  end

  test "test to_digits(negative one)" do
    assert {[1], 1, -1} == Digits.to_digits(-1.0)
  end

  test "test to_digits(small denormalized number)" do
    # 4.94065645841246544177e-324
    <<small_denorm::float>> = <<0, 0, 0, 0, 0, 0, 0, 1>>

    assert {[4, 9, 4, 0, 6, 5, 6, 4, 5, 8, 4, 1, 2, 4, 6, 5, 4], -323, 1} ==
             Digits.to_digits(small_denorm)
  end

  test "test to_digits(large denormalized number)" do
    # 2.22507385850720088902e-308
    <<large_denorm::float>> = <<0, 15, 255, 255, 255, 255, 255, 255>>

    assert {[2, 2, 2, 5, 0, 7, 3, 8, 5, 8, 5, 0, 7, 2, 0, 1], -307, 1} ==
             Digits.to_digits(large_denorm)
  end

  test "test to_digits(small normalized number)" do
    # 2.22507385850720138309e-308
    <<small_norm::float>> = <<0, 16, 0, 0, 0, 0, 0, 0>>

    assert {[2, 2, 2, 5, 0, 7, 3, 8, 5, 8, 5, 0, 7, 2, 0, 1, 4], -307, 1} ==
             Digits.to_digits(small_norm)
  end

  test "test to_digits(large normalized number)" do
    # 1.79769313486231570815e+308
    <<large_norm::float>> = <<127, 239, 255, 255, 255, 255, 255, 255>>

    assert {[1, 7, 9, 7, 6, 9, 3, 1, 3, 4, 8, 6, 2, 3, 1, 5, 7], 309, 1} ==
             Digits.to_digits(large_norm)
  end

  test "test frexp(zero)" do
    assert {0.0, 0} == Digits.frexp(0.0)
  end

  test "test frexp(one)" do
    assert {0.5, 1} == Digits.frexp(1.0)
  end

  test "test frexp(negative one)" do
    assert {-0.5, 1} == Digits.frexp(-1.0)
  end

  test "test frexp(small denormalized number)" do
    # 4.94065645841246544177e-324
    <<small_denorm::float>> = <<0, 0, 0, 0, 0, 0, 0, 1>>
    assert {0.5, -1073} == Digits.frexp(small_denorm)
  end

  test "test frexp(large denormalized number)" do
    # 2.22507385850720088902e-308
    <<large_denorm::float>> = <<0, 15, 255, 255, 255, 255, 255, 255>>
    assert {0.99999999999999978, -1022} == Digits.frexp(large_denorm)
  end

  test "test frexp(small normalized number)" do
    # 2.22507385850720138309e-308
    <<small_norm::float>> = <<0, 16, 0, 0, 0, 0, 0, 0>>
    assert {0.5, -1021} == Digits.frexp(small_norm)
  end

  test "test frexp(large normalized number)" do
    # 1.79769313486231570815e+308
    <<large_norm::float>> = <<127, 239, 255, 255, 255, 255, 255, 255>>
    assert {0.99999999999999989, 1024} == Digits.frexp(large_norm)
  end
end
