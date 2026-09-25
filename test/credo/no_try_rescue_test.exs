Code.require_file("../../credo/checks/no_try_rescue.ex", __DIR__)

defmodule Localize.Credo.NoTryRescueTest do
  use Credo.Test.Case

  alias Localize.Credo.NoTryRescue

  setup_all do
    {:ok, _applications} = Application.ensure_all_started(:credo)
    :ok
  end

  describe "reports" do
    test "a try/rescue" do
      """
      defmodule Sample do
        def parse(text) do
          try do
            decode(text)
          rescue
            _exception -> nil
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoTryRescue)
      |> assert_issue()
    end

    test "a try/catch" do
      """
      defmodule Sample do
        def parse(text) do
          try do
            decode(text)
          catch
            _kind, _reason -> nil
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoTryRescue)
      |> assert_issue()
    end

    test "a function-level rescue" do
      """
      defmodule Sample do
        defp parse(text) do
          decode(text)
        rescue
          _exception -> nil
        end
      end
      """
      |> to_source_file()
      |> run_check(NoTryRescue)
      |> assert_issue()
    end

    test "a function-level catch" do
      """
      defmodule Sample do
        def parse(text) do
          decode(text)
        catch
          :exit, _reason -> nil
        end
      end
      """
      |> to_source_file()
      |> run_check(NoTryRescue)
      |> assert_issue()
    end

    test "a try/after in a function that is not agreed" do
      """
      defmodule Sample do
        def with_resource(resource, fun) do
          open(resource)

          try do
            fun.()
          after
            close(resource)
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoTryRescue)
      |> assert_issue()
    end

    test "a function-level after in a function that is not agreed" do
      """
      defmodule Sample do
        def with_resource(resource, fun) do
          fun.(resource)
        after
          close(resource)
        end
      end
      """
      |> to_source_file()
      |> run_check(NoTryRescue)
      |> assert_issue()
    end

    test "a try/after that also rescues, even in an agreed function" do
      """
      defmodule Sample do
        def with_resource(resource, fun) do
          try do
            fun.()
          rescue
            _exception -> nil
          after
            close(resource)
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoTryRescue, allowed_try_after: [{Sample, :with_resource, 2}])
      |> assert_issue()
    end

    test "a rescue of anything but ArgumentError around String.to_existing_atom/1" do
      """
      defmodule Sample do
        def existing_atom(text) do
          String.to_existing_atom(text)
        rescue
          _exception -> nil
        end
      end
      """
      |> to_source_file()
      |> run_check(NoTryRescue)
      |> assert_issue()
    end

    test "a rescue of ArgumentError around more than a String.to_existing_atom/1 call" do
      """
      defmodule Sample do
        def existing_atom(text) do
          String.to_existing_atom(String.downcase(text))
        rescue
          ArgumentError -> nil
        end
      end
      """
      |> to_source_file()
      |> run_check(NoTryRescue)
      |> assert_issue()
    end
  end

  describe "allows" do
    test "a rescue of ArgumentError around String.to_existing_atom/1" do
      """
      defmodule Sample do
        def existing_atom(text) do
          String.to_existing_atom(text)
        rescue
          ArgumentError -> nil
        end
      end
      """
      |> to_source_file()
      |> run_check(NoTryRescue)
      |> refute_issues()
    end

    test "a try rescuing ArgumentError around :erlang.binary_to_existing_atom/2" do
      """
      defmodule Sample do
        def existing_atom(text) do
          try do
            :erlang.binary_to_existing_atom(text, :utf8)
          rescue
            _exception in ArgumentError -> nil
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoTryRescue)
      |> refute_issues()
    end

    test "a try/after in an agreed function of a nested module" do
      """
      defmodule Outer do
        defmodule Inner do
          def with_resource(resource, fun) do
            try do
              fun.()
            after
              close(resource)
            end
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoTryRescue, allowed_try_after: [{Outer.Inner, :with_resource, 2}])
      |> refute_issues()
    end

    test "code with no try" do
      """
      defmodule Sample do
        def parse(text) do
          case decode(text) do
            {:ok, value} -> value
            {:error, _reason} -> nil
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoTryRescue)
      |> refute_issues()
    end
  end
end
