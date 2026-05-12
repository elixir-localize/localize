defmodule Localize.Locale.Provider.CacheSafeTest do
  @moduledoc """
  Security regression: locale cache files are decoded with `[:safe]`
  so a malicious or corrupted file in `:locale_cache_dir` cannot grow
  the atom table or instantiate funs/refs in the running BEAM.
  """

  use ExUnit.Case, async: false

  alias Localize.Locale.Provider.Cache

  @tmp_dir Path.join(
             System.tmp_dir!(),
             "localize_cache_safe_test_#{:erlang.unique_integer([:positive])}"
           )

  setup do
    File.mkdir_p!(@tmp_dir)

    original_cache_dir = Application.get_env(:localize, :locale_cache_dir)
    Application.put_env(:localize, :locale_cache_dir, @tmp_dir)

    on_exit(fn ->
      File.rm_rf!(@tmp_dir)

      if original_cache_dir do
        Application.put_env(:localize, :locale_cache_dir, original_cache_dir)
      else
        Application.delete_env(:localize, :locale_cache_dir)
      end
    end)

    :ok
  end

  test "rejects an ETF file referencing a never-seen atom rather than creating it" do
    locale_id = :localize_cache_safe_test_dummy
    file_path = Cache.path(locale_id)

    # Build an ETF that mentions a unique atom-like binary that has
    # never been interned. Using `:erlang.term_to_binary/1` directly
    # would require the atom to exist already; build the wire form by
    # hand instead.
    bogus_atom_name = "ZZZ_cache_safe_atom_#{:erlang.unique_integer([:positive])}"

    # External term format: 131 (version), 0x77 (small_atom_utf8_ext),
    # then <len-byte> <utf-8 bytes>. We avoid `term_to_binary/1` (which
    # would require the atom to exist already) by writing the wire
    # form directly.
    encoded_atom = <<0x77, byte_size(bogus_atom_name)::size(8), bogus_atom_name::binary>>
    ext_term = <<131, encoded_atom::binary>>

    File.write!(file_path, ext_term)

    # The atom must not exist before the call.
    assert nil == Localize.Utils.Helpers.existing_atom(bogus_atom_name)

    # Decoding via the cache must refuse to create the atom and instead
    # surface the file as not-loadable.
    assert true == Cache.stale?(locale_id)
    assert nil == Localize.Utils.Helpers.existing_atom(bogus_atom_name)
  end
end
