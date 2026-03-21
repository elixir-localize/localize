if Code.ensure_loaded?(Localize.Message.Interpreter) do
  defmodule Localize.Message.FormatErrorTest do
    use ExUnit.Case, async: true

    @opts [formatter_backend: :elixir]

    defp format_error(source, bindings) do
      case Localize.Message.format(source, bindings, @opts) do
        {:error, %{__exception__: true} = exception} ->
          {:error, Exception.message(exception)}

        other ->
          other
      end
    end

    if Code.ensure_loaded?(Localize.Number) do
      describe "invalid bindings for :number" do
        test "non-numeric string returns error" do
          {:error, reason} = format_error("{$x :number}", %{"x" => "hello"})
          assert reason =~ "cannot parse"
          assert reason =~ "as a number"
        end

        test "list returns error" do
          {:error, reason} = format_error("{$x :number}", %{"x" => [1, 2, 3]})
          assert reason =~ "cannot format"
          assert reason =~ "as a number"
        end

        test "map returns error" do
          {:error, reason} = format_error("{$x :number}", %{"x" => %{a: 1}})
          assert reason =~ "cannot format"
          assert reason =~ "as a number"
        end

        test "boolean returns error" do
          {:error, reason} = format_error("{$x :number}", %{"x" => true})
          assert reason =~ "cannot format"
          assert reason =~ "as a number"
        end
      end

      describe "invalid bindings for :integer" do
        test "non-numeric string returns error" do
          {:error, reason} = format_error("{$x :integer}", %{"x" => "abc"})
          assert reason =~ "cannot parse"
          assert reason =~ "as a number"
        end
      end

      describe "invalid bindings for :percent" do
        test "non-numeric string returns error" do
          {:error, reason} = format_error("{$x :percent}", %{"x" => "xyz"})
          assert reason =~ "cannot parse"
          assert reason =~ "as a number"
        end

        test "Date struct returns error" do
          {:error, reason} = format_error("{$x :percent}", %{"x" => ~D[2024-01-01]})
          assert reason =~ "cannot format"
          assert reason =~ "as a number"
        end
      end

      describe "invalid bindings for :currency" do
        test "non-numeric string returns error" do
          {:error, reason} =
            format_error("{$x :currency currency=USD}", %{"x" => "abc"})

          assert reason =~ "as a number"
        end

        test "Date struct returns error" do
          {:error, reason} =
            format_error("{$x :currency currency=USD}", %{"x" => ~D[2024-01-01]})

          assert reason =~ "cannot format"
          assert reason =~ "as a number"
        end
      end

      describe "invalid numbering system" do
        test "unknown numbering system returns error" do
          {:error, reason} =
            format_error("{$x :number numberingSystem=bogus}", %{"x" => 42})

          assert reason =~ "bogus"
        end
      end

      describe "invalid bindings in .input declarations" do
        test "returns error for invalid type in .input" do
          message = """
          .input {$count :number}
          .match $count
            1 {{one item}}
            * {{{$count} items}}
          """

          {:error, reason} = format_error(message, %{"count" => "hello"})
          assert reason =~ "as a number"
        end
      end

      describe "cross-type mismatches (number)" do
        test "Date to :number returns error" do
          {:error, reason} = format_error("{$x :number}", %{"x" => ~D[2024-01-01]})
          assert reason =~ "cannot format"
          assert reason =~ "as a number"
        end

        test "list to :currency returns error" do
          {:error, _reason} =
            format_error("{$x :currency currency=USD}", %{"x" => [1]})
        end
      end

      describe "format errors inside .match variant bodies" do
        test "returns error when variant body has invalid type" do
          message = """
          .input {$gender :string}
          .match $gender
            male {{He bought {$price :number} items.}}
            * {{They bought {$price :number} items.}}
          """

          {:error, reason} =
            format_error(message, %{"gender" => "male", "price" => [1, 2]})

          assert reason =~ "cannot format"
          assert reason =~ "as a number"
        end
      end
    end

    describe "invalid bindings for :date" do
      test "number returns error" do
        {:error, reason} = format_error("{$x :date}", %{"x" => 42})
        assert reason =~ "cannot format"
        assert reason =~ "as a date"
      end

      test "unparseable string returns error" do
        {:error, reason} = format_error("{$x :date}", %{"x" => "not-a-date"})
        assert reason =~ "cannot parse"
        assert reason =~ "as a date"
      end

      test "list returns error" do
        {:error, reason} = format_error("{$x :date}", %{"x" => [2024, 1, 1]})
        assert reason =~ "cannot format"
        assert reason =~ "as a date"
      end
    end

    describe "invalid bindings for :time" do
      test "number returns error" do
        {:error, reason} = format_error("{$x :time}", %{"x" => 42})
        assert reason =~ "cannot format"
        assert reason =~ "as a datetime"
      end

      test "unparseable string returns error" do
        {:error, reason} = format_error("{$x :time}", %{"x" => "not-a-time"})
        assert reason =~ "cannot parse"
        assert reason =~ "as a datetime"
      end
    end

    describe "invalid bindings for :datetime" do
      test "number returns error" do
        {:error, reason} = format_error("{$x :datetime}", %{"x" => 42})
        assert reason =~ "cannot format"
        assert reason =~ "as a datetime"
      end

      test "unparseable string returns error" do
        {:error, reason} = format_error("{$x :datetime}", %{"x" => "garbage"})
        assert reason =~ "cannot parse"
        assert reason =~ "as a datetime"
      end

      test "list returns error" do
        {:error, reason} = format_error("{$x :datetime}", %{"x" => [1, 2, 3]})
        assert reason =~ "cannot format"
        assert reason =~ "as a datetime"
      end
    end

    if Code.ensure_loaded?(Localize.Unit.Formatter) do
      describe "invalid bindings for :unit" do
        test "Date struct returns error" do
          {:error, reason} =
            format_error("{$x :unit unit=kilometer}", %{"x" => ~D[2024-01-01]})

          assert reason =~ "cannot format"
          assert reason =~ "as a number"
        end

        test "missing unit option returns error" do
          {:error, reason} = format_error("{$x :unit}", %{"x" => 5})
          assert reason =~ "requires a `unit` option"
        end

        test "non-numeric string returns error" do
          {:error, reason} =
            format_error("{$x :unit unit=kilometer}", %{"x" => "abc"})

          assert reason =~ "as a number"
        end
      end

      describe "invalid unit names" do
        test "invalid unit name returns error" do
          {:error, _reason} =
            format_error("{$x :unit unit=invalid_xyz}", %{"x" => 5})
        end

        test "invalid unit name with struct returns error" do
          unit = Localize.Unit.new!(3, "kilometer")

          {:error, _reason} =
            format_error("{$x :unit unit=invalid_xyz}", %{"x" => unit})
        end
      end
    end
  end
end
