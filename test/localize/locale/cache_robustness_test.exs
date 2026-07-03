defmodule Localize.Locale.Provider.CacheRobustnessTest do
  # async: false because the tests point the global
  # :locale_cache_dir configuration at a per-test temporary
  # directory.
  use ExUnit.Case, async: false

  alias Localize.Locale.Provider.Cache

  @locale_id :"xx-CACHETEST"

  setup context do
    tmp_dir = context.tmp_dir
    previous = Application.get_env(:localize, :locale_cache_dir)
    Application.put_env(:localize, :locale_cache_dir, tmp_dir)

    on_exit(fn ->
      if previous do
        Application.put_env(:localize, :locale_cache_dir, previous)
      else
        Application.delete_env(:localize, :locale_cache_dir)
      end
    end)

    :ok
  end

  describe "corrupt cache files" do
    @tag :tmp_dir
    test "get/1 treats an undecodable file as a cache miss, not a crash" do
      path = Cache.path(@locale_id)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "not an external term format binary")

      assert {:error, %Localize.LocaleNotFoundInCacheError{}} = Cache.get(@locale_id)
    end

    @tag :tmp_dir
    test "get/1 treats a truncated ETF file as a cache miss" do
      path = Cache.path(@locale_id)
      File.mkdir_p!(Path.dirname(path))
      complete = :erlang.term_to_binary(%{version: Localize.version(), data: "payload"})
      truncated = binary_part(complete, 0, byte_size(complete) - 3)
      File.write!(path, truncated)

      assert {:error, %Localize.LocaleNotFoundInCacheError{}} = Cache.get(@locale_id)
    end

    @tag :tmp_dir
    test "stale?/1 reports a corrupt file as stale, not a crash" do
      path = Cache.path(@locale_id)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, <<131, 1, 2, 3>>)

      assert Cache.stale?(@locale_id)
    end
  end

  describe "atomic writes" do
    @tag :tmp_dir
    test "store/2 leaves no temporary files behind", %{tmp_dir: tmp_dir} do
      content = :erlang.term_to_binary(%{version: Localize.version()})

      assert {:ok, path} = Cache.store(@locale_id, content)
      assert File.read!(path) == content
      assert [Path.basename(path)] == File.ls!(tmp_dir)
    end

    @tag :tmp_dir
    test "store/2 atomically replaces an existing cache file" do
      first = :erlang.term_to_binary(%{version: Localize.version(), n: 1})
      second = :erlang.term_to_binary(%{version: Localize.version(), n: 2})

      assert {:ok, path} = Cache.store(@locale_id, first)
      assert {:ok, ^path} = Cache.store(@locale_id, second)
      assert File.read!(path) == second
    end
  end
end
