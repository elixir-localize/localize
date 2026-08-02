defmodule Mix.Tasks.Localize.Unit.GenConversionsTest do
  use ExUnit.Case, async: false

  # The task writes a file and the test compiles it, so the generated
  # modules must not collide across tests — each gets its own name and
  # its own tmp_dir.

  alias Mix.Tasks.Localize.Unit.GenConversions

  # Values spanning the range a fit could plausibly go wrong over,
  # including 0 (which only an offset unit distinguishes) and a large
  # value (which a saturating scale would fail).
  @values [0, 1, 2.5, 7, 30, 100, 1000]

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  # Drains the Mix.Shell.Process mailbox into flat strings. The task
  # emits IO lists carrying ANSI codes, so the parts are flattened and
  # the non-binary codes dropped.
  defp shell_messages(acc \\ []) do
    receive do
      {:mix_shell, :info, [message]} ->
        text =
          message
          |> List.wrap()
          |> Enum.filter(&is_binary/1)
          |> Enum.join()

        shell_messages([text | acc])
    after
      0 -> acc
    end
  end

  defp generate!(types, module, tmp_dir) do
    path = Path.join(tmp_dir, "#{Macro.underscore(module)}.ex")

    GenConversions.run([
      "--types",
      Enum.join(types, ","),
      "--module",
      module,
      "--output",
      path
    ])

    [{compiled, _bytecode}] = Code.compile_file(path)
    {compiled, path}
  end

  describe "generated conversions agree with Localize" do
    for {quantity, sample} <- [
          {"force", "pound-force"},
          {"acceleration", "g-force"},
          {"angle", "degree"}
        ] do
      @quantity quantity
      @sample sample

      @tag :tmp_dir
      test "#{quantity}: every unit round-trips against Localize", %{tmp_dir: tmp_dir} do
        module = "GenTest.#{Macro.camelize(String.replace(@quantity, "-", "_"))}"
        {generated, _path} = generate!([@quantity], module, tmp_dir)

        assert generated.known_units() != []

        for unit <- generated.known_units(), value <- @values do
          assert {:ok, {got, base}} = generated.to_base(value, unit)
          assert {:ok, want} = Localize.Unit.Conversion.convert(value, unit, base)

          assert_in_delta got,
                          want,
                          max(abs(want) * 1.0e-9, 1.0e-9),
                          "#{unit} at #{value}: generated #{got}, Localize #{want}"
        end
      end

      @tag :tmp_dir
      test "#{quantity}: includes its representative unit #{sample}", %{tmp_dir: tmp_dir} do
        module = "GenSample.#{Macro.camelize(String.replace(@quantity, "-", "_"))}"
        {generated, _path} = generate!([@quantity], module, tmp_dir)

        assert @sample in generated.known_units()
      end
    end
  end

  describe "flexible unit spellings" do
    @tag :tmp_dir
    test "resolves identifiers, spaced names and English symbols alike", %{tmp_dir: tmp_dir} do
      {generated, _path} = generate!(["angle", "force"], "GenAliases.Units", tmp_dir)

      canonical = generated.to_base(90, "degree")

      assert generated.to_base(90, "degrees") == canonical
      assert generated.to_base(90, "DEGREE") == canonical
      assert generated.to_base(90, "  degree  ") == canonical
    end

    @tag :tmp_dir
    test "an unknown unit is an error, not a crash", %{tmp_dir: tmp_dir} do
      {generated, _path} = generate!(["force"], "GenUnknown.Units", tmp_dir)

      assert {:error, {:unknown_unit, "furlong-per-fortnight"}} =
               generated.to_base(1, "furlong-per-fortnight")
    end
  end

  describe "SI prefixes and compounds outside the table" do
    @tag :tmp_dir
    test "an SI-prefixed unit converts without being tabulated", %{tmp_dir: tmp_dir} do
      {generated, _path} = generate!(["force"], "GenPrefix.Units", tmp_dir)

      refute "millinewton" in generated.known_units()

      assert {:ok, {got, base}} = generated.to_base(1000, "millinewton")
      assert {:ok, want} = Localize.Unit.Conversion.convert(1000, "millinewton", base)
      assert_in_delta got, want, 1.0e-9
    end

    @tag :tmp_dir
    test "a compound built from tabulated units converts", %{tmp_dir: tmp_dir} do
      {generated, _path} = generate!(["length", "duration"], "GenCompound.Units", tmp_dir)

      assert {:ok, {got, "meter-per-second"}} = generated.to_base(36, "kilometer-per-hour")
      assert_in_delta got, 10.0, 1.0e-9
    end
  end

  describe "non-affine and offset units" do
    @tag :tmp_dir
    test "a non-affine unit is skipped rather than tabulated wrongly", %{tmp_dir: tmp_dir} do
      {generated, _path} = generate!(["speed"], "GenSpeed.Units", tmp_dir)

      # Beaufort saturates, so no factor/offset pair can represent it.
      refute "beaufort" in generated.known_units()

      # The skip must be announced, not silent — a quietly missing unit
      # is indistinguishable from one CLDR never had.
      assert Enum.any?(shell_messages(), &String.contains?(&1, "skipping beaufort"))
    end

    @tag :tmp_dir
    test "an offset unit is refused inside a prefix or compound", %{tmp_dir: tmp_dir} do
      {generated, _path} = generate!(["temperature"], "GenOffset.Units", tmp_dir)

      # Celsius itself converts, carrying its offset.
      assert {:ok, {373.15, "kelvin"}} = generated.to_base(100, "celsius")

      # But scaling or dividing an offset unit is not meaningful.
      assert {:error, {:unknown_unit, _}} = generated.to_base(1, "kilocelsius")
      assert {:error, {:unknown_unit, _}} = generated.to_base(1, "celsius-per-hour")
    end
  end

  describe "task arguments" do
    test "rejects an unknown quantity" do
      assert_raise Mix.Error, ~r/Unknown quantities: nonsense/, fn ->
        GenConversions.run(["--types", "nonsense"])
      end
    end

    test "requires --types" do
      assert_raise Mix.Error, ~r/--types is required/, fn ->
        GenConversions.run([])
      end
    end
  end
end
