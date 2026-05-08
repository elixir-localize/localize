defmodule Localize.Utils.Math.RoundingTest do
  use ExUnit.Case, async: true

  alias Localize.Utils.Math

  def round(number, precision \\ 0, rounding \\ :half_up) do
    Math.round(number, precision, rounding)
  end

  def ceil(number, precision \\ 0) do
    round(number, precision, :ceiling)
  end

  def floor(number, precision \\ 0) do
    round(number, precision, :floor)
  end

  test "rounding to less than the precision of the number returns 0" do
    assert Math.round(1.235e-4, 3, :half_even) == 0.0
  end

  for mode <- Localize.Utils.Math.rounding_modes() do
    number = 100_000.00

    test "rounding 100_000.00 with mode #{inspect(mode)}" do
      assert unquote(number) == Math.round(unquote(number), 2, unquote(mode))
    end
  end

  test "Simple round :half_up" do
    assert 1.21 == round(1.205, 2)
    assert 1.22 == round(1.215, 2)
    assert 1.23 == round(1.225, 2)
    assert 1.24 == round(1.235, 2)
    assert 1.25 == round(1.245, 2)
    assert 1.26 == round(1.255, 2)
    assert 1.27 == round(1.265, 2)
    assert 1.28 == round(1.275, 2)
    assert 1.29 == round(1.285, 2)
    assert 1.30 == round(1.295, 2)
  end

  test "Simple round :half_even" do
    assert 1.20 == round(1.205, 2, :half_even)
    assert 1.22 == round(1.215, 2, :half_even)
    assert 1.22 == round(1.225, 2, :half_even)
    assert 1.24 == round(1.235, 2, :half_even)
    assert 1.24 == round(1.245, 2, :half_even)
    assert 1.26 == round(1.255, 2, :half_even)
    assert 1.26 == round(1.265, 2, :half_even)
    assert 1.28 == round(1.275, 2, :half_even)
    assert 1.28 == round(1.285, 2, :half_even)
    assert 1.30 == round(1.295, 2, :half_even)
  end

  test "test ceil" do
    assert 1.21 == ceil(1.204, 2)
    assert 1.21 == ceil(1.205, 2)
    assert 1.21 == ceil(1.206, 2)

    assert 1.22 == ceil(1.214, 2)
    assert 1.22 == ceil(1.215, 2)
    assert 1.22 == ceil(1.216, 2)

    assert -1.20 == ceil(-1.204, 2)
    assert -1.20 == ceil(-1.205, 2)
    assert -1.20 == ceil(-1.206, 2)
  end

  test "test floor" do
    assert 1.20 == floor(1.204, 2)
    assert 1.20 == floor(1.205, 2)
    assert 1.20 == floor(1.206, 2)

    assert 1.21 == floor(1.214, 2)
    assert 1.21 == floor(1.215, 2)
    assert 1.21 == floor(1.216, 2)

    assert -1.21 == floor(-1.204, 2)
    assert -1.21 == floor(-1.205, 2)
    assert -1.21 == floor(-1.206, 2)
  end
end
