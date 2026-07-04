defmodule Localize.Collation.TableTest do
  # async: false — the reload tests below erase and restore
  # :persistent_term entries shared by the whole collation subsystem.
  use ExUnit.Case, async: false

  alias Localize.Collation.Table

  @fast_latin_key {:localize, :collation_fast_latin}

  setup_all do
    Localize.Collation.ensure_loaded()
    :ok
  end

  describe "lookup/1 with codepoint lists" do
    test "finds a contraction entry for a codepoint sequence" do
      # L + MIDDLE DOT is a CLDR context contraction in the root table.
      assert {:ok, elements} = Table.lookup([0x004C, 0x00B7])
      assert is_list(elements)
      assert length(elements) >= 2
    end

    test "returns :unmapped for a sequence with no entry" do
      assert :unmapped = Table.lookup([0x004C, 0x0041])
    end
  end

  describe "contraction_starters/1" do
    test "returns contraction lengths for a contraction starter" do
      lengths = Table.contraction_starters(0x004C)
      assert 2 in lengths
    end

    test "returns an empty list for a non-starter" do
      assert Table.contraction_starters(?q) == []
    end
  end

  describe "longest_match/1" do
    test "matches the longest contraction first" do
      assert {[0x004C, 0x00B7], elements, [?a]} = Table.longest_match([0x004C, 0x00B7, ?a])
      assert is_list(elements)
    end

    test "falls back to a single codepoint when no contraction completes" do
      assert {[0x004C], _elements, [?x]} = Table.longest_match([0x004C, ?x])
    end

    test "reports an unmapped codepoint" do
      assert {:unmapped, 0x10FFFF, [?a]} = Table.longest_match([0x10FFFF, ?a])
    end

    test "returns :done for an empty list" do
      assert :done = Table.longest_match([])
    end
  end

  describe "lookup_with_overlay/2" do
    test "nil overlay behaves like a root lookup" do
      assert Table.lookup_with_overlay(?a, nil) == Table.lookup(?a)
      assert :unmapped = Table.lookup_with_overlay(0x10FFFF, nil)
    end

    test "overlay entries take precedence over the root table" do
      overlay = %{?a => [{0x9999, 0x0020, 0x0002, false}]}
      assert {:ok, [{0x9999, 0x0020, 0x0002, false}]} = Table.lookup_with_overlay(?a, overlay)
    end

    test "misses in the overlay fall back to the root table" do
      overlay = %{?a => [{0x9999, 0x0020, 0x0002, false}]}
      assert Table.lookup_with_overlay(?b, overlay) == Table.lookup(?b)
    end

    test "returns :unmapped when neither overlay nor table match" do
      overlay = %{?a => [{0x9999, 0x0020, 0x0002, false}]}
      assert :unmapped = Table.lookup_with_overlay(0x10FFFF, overlay)
    end

    test "looks up codepoint lists against the overlay" do
      overlay = %{{?c, ?h} => [{0x9999, 0x0020, 0x0002, false}]}

      assert {:ok, [{0x9999, 0x0020, 0x0002, false}]} =
               Table.lookup_with_overlay([?c, ?h], overlay)
    end
  end

  describe "longest_match_with_overlay/2" do
    test "nil overlay delegates to longest_match/1" do
      assert Table.longest_match_with_overlay([?a, ?b], nil) == Table.longest_match([?a, ?b])
    end

    test "matches overlay contractions before root entries" do
      overlay = %{{?c, ?h} => [{0x9999, 0x0020, 0x0002, false}]}

      assert {[?c, ?h], [{0x9999, 0x0020, 0x0002, false}], [?x]} =
               Table.longest_match_with_overlay([?c, ?h, ?x], overlay)
    end

    test "matches single-codepoint overlay entries" do
      overlay = %{?a => [{0x9999, 0x0020, 0x0002, false}]}

      assert {[?a], [{0x9999, 0x0020, 0x0002, false}], [?b]} =
               Table.longest_match_with_overlay([?a, ?b], overlay)
    end

    test "falls back to the root table when the overlay does not match" do
      overlay = %{?a => [{0x9999, 0x0020, 0x0002, false}]}

      assert Table.longest_match_with_overlay([?z], overlay) == Table.longest_match([?z])
    end

    test "returns :done for an empty list" do
      assert :done = Table.longest_match_with_overlay([], %{})
      assert :done = Table.longest_match_with_overlay([], nil)
    end
  end

  describe "ensure_loaded/0 reload path" do
    test "reloads erased persistent_term entries through the GenServer" do
      # Erase one of the keys ensure_loaded checks, forcing the
      # GenServer :load call and the full reload from the ETF.
      :persistent_term.erase(@fast_latin_key)

      assert :ok = Table.ensure_loaded()
      assert is_tuple(:persistent_term.get(@fast_latin_key))
      assert {:ok, _elements} = Table.lookup(?a)
    end
  end

  describe "start_link/1" do
    test "returns already_started when the table server is running" do
      assert {:error, {:already_started, pid}} = Table.start_link([])
      assert is_pid(pid)
    end
  end
end
