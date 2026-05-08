defmodule GenerateNumber do
  @moduledoc false
  require ExUnitProperties

  def decimal do
    ExUnitProperties.gen all(float <- StreamData.float()) do
      Decimal.from_float(float)
    end
  end

  def float do
    ExUnitProperties.gen all(
                           float <- StreamData.float(min: -999_999_999_999, max: 999_999_999_999)
                         ) do
      float
    end
  end

  def integer do
    ExUnitProperties.gen all(integer <- StreamData.integer()) do
      integer
    end
  end
end
