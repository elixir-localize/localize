defmodule Localize.PrivTest do
  @moduledoc """
  Covers finding Localize's `priv` directory inside an escript, where the
  application directory lies within the escript's archive (issue #58).

  """

  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  @with_priv [
    {~c"localize/ebin/localize.app", "{application, localize, []}."},
    {~c"localize/priv/localize/version", "49"},
    {~c"localize/priv/localize/supplemental_data/number_systems.etf", :erlang.term_to_binary(%{})}
  ]

  # Writes an escript as `mix escript.build` does: a shebang line, then a
  # zip archive with each application's `ebin`, and `priv` when the escript
  # is built with `include_priv_for`. A rebuild is dated a second after the
  # build it replaces, as `mix escript.build` takes longer than that.
  defp build(path, entries) do
    {:ok, {_name, archive}} = :zip.create(~c"probe.zip", entries, [:memory])
    previous = File.stat(path, time: :posix)
    :ok = :escript.create(String.to_charlist(path), [:shebang, {:archive, archive}])

    with {:ok, %File.Stat{mtime: mtime}} <- previous do
      File.touch!(path, mtime + 1)
    end

    path
  end

  defp escript(tmp_dir, entries), do: build(Path.join(tmp_dir, "probe"), entries)

  defp download(priv) do
    downloaded = Path.join(priv, "localize/locales/fr.etf")
    File.mkdir_p!(Path.dirname(downloaded))
    File.write!(downloaded, "downloaded")
    downloaded
  end

  test "extracts Localize's data from an escript's archive", %{tmp_dir: tmp_dir} do
    escript = escript(tmp_dir, @with_priv)
    cache_root = Path.join(tmp_dir, "cache")

    assert {:ok, priv} = Localize.Priv.extract(escript, cache_root)
    assert Path.dirname(priv) == cache_root
    assert File.read!(Path.join(priv, "localize/version")) == "49"
    assert File.regular?(Path.join(priv, "localize/supplemental_data/number_systems.etf"))
    assert Path.wildcard(Path.join(cache_root, "**/*.app")) == []
  end

  test "an unchanged escript reuses its copy without reading the archive", %{tmp_dir: tmp_dir} do
    escript = escript(tmp_dir, @with_priv)
    cache_root = Path.join(tmp_dir, "cache")

    assert {:ok, priv} = Localize.Priv.extract(escript, cache_root)
    downloaded = download(priv)

    # The same size and modification time, but no longer an escript: a
    # start that read the archive would fail.
    %File.Stat{size: size, mtime: mtime} = File.stat!(escript, time: :posix)
    File.write!(escript, :binary.copy("x", size))
    File.touch!(escript, mtime)

    assert {:ok, ^priv} = Localize.Priv.extract(escript, cache_root)
    assert File.read!(downloaded) == "downloaded"
  end

  test "a rebuild carrying the same data shares the copy and its downloads", %{tmp_dir: tmp_dir} do
    escript = escript(tmp_dir, @with_priv)
    cache_root = Path.join(tmp_dir, "cache")

    assert {:ok, priv} = Localize.Priv.extract(escript, cache_root)
    downloaded = download(priv)

    build(escript, [{~c"escript_probe/ebin/escript_probe.beam", "changed code"} | @with_priv])

    assert {:ok, ^priv} = Localize.Priv.extract(escript, cache_root)
    assert File.read!(downloaded) == "downloaded"
    assert Path.wildcard(Path.join(cache_root, "data-*")) == [priv]
  end

  test "a rebuild carrying different data gets a copy of its own", %{tmp_dir: tmp_dir} do
    escript = escript(tmp_dir, @with_priv)
    cache_root = Path.join(tmp_dir, "cache")

    assert {:ok, first} = Localize.Priv.extract(escript, cache_root)

    version = ~c"localize/priv/localize/version"
    build(escript, List.keyreplace(@with_priv, version, 0, {version, "50"}))

    assert {:ok, second} = Localize.Priv.extract(escript, cache_root)
    assert second != first
    assert File.read!(Path.join(second, "localize/version")) == "50"
    assert File.read!(Path.join(first, "localize/version")) == "49"
  end

  test "escripts carrying the same data share one copy", %{tmp_dir: tmp_dir} do
    cache_root = Path.join(tmp_dir, "cache")
    first = build(Path.join(tmp_dir, "first"), @with_priv)
    second = build(Path.join(tmp_dir, "second"), Enum.reverse(@with_priv))

    assert {:ok, priv} = Localize.Priv.extract(first, cache_root)
    assert {:ok, ^priv} = Localize.Priv.extract(second, cache_root)
    assert [_, _] = Path.wildcard(Path.join(cache_root, "escript-*"))
  end

  test "a copy deleted from the cache is extracted again", %{tmp_dir: tmp_dir} do
    escript = escript(tmp_dir, @with_priv)
    cache_root = Path.join(tmp_dir, "cache")

    assert {:ok, priv} = Localize.Priv.extract(escript, cache_root)
    File.rm_rf!(priv)

    assert {:ok, ^priv} = Localize.Priv.extract(escript, cache_root)
    assert File.read!(Path.join(priv, "localize/version")) == "49"
  end

  test "a record naming something other than a copy is ignored", %{tmp_dir: tmp_dir} do
    escript = escript(tmp_dir, @with_priv)
    cache_root = Path.join(tmp_dir, "cache")

    assert {:ok, priv} = Localize.Priv.extract(escript, cache_root)
    [record] = Path.wildcard(Path.join(cache_root, "escript-*"))
    %File.Stat{size: size, mtime: mtime} = File.stat!(escript, time: :posix)
    "data-" <> key = Path.basename(priv)

    # The first resolves to a directory that exists, above the cache.
    for key <- ["#{key}/../..", "../../elsewhere", "", "not a key"] do
      File.write!(record, "#{size}-#{mtime} #{key}")
      assert {:ok, ^priv} = Localize.Priv.extract(escript, cache_root)
    end
  end

  # An archive built from a directory tree lists each directory as an
  # entry of its own, as `mix escript.build` does not.
  test "an archive listing its directories is extracted", %{tmp_dir: tmp_dir} do
    tree = Path.join(tmp_dir, "tree")
    File.mkdir_p!(Path.join(tree, "localize/priv/localize"))
    File.write!(Path.join(tree, "localize/priv/localize/version"), "49")

    {:ok, {_name, archive}} =
      :zip.create(~c"probe.zip", [~c"localize"], [:memory, cwd: String.to_charlist(tree)])

    escript = Path.join(tmp_dir, "probe")
    :ok = :escript.create(String.to_charlist(escript), [:shebang, {:archive, archive}])

    assert {:ok, priv} = Localize.Priv.extract(escript, Path.join(tmp_dir, "cache"))
    assert File.read!(Path.join(priv, "localize/version")) == "49"
  end

  test "an entry outside Localize's data is refused", %{tmp_dir: tmp_dir} do
    escript = escript(tmp_dir, [{~c"localize/priv/../../evil", "written"} | @with_priv])
    cache_root = Path.join(tmp_dir, "cache")

    assert {:error, message} = Localize.Priv.extract(escript, cache_root)
    assert message =~ "localize/priv/../../evil"
    refute File.exists?(Path.join(tmp_dir, "evil"))
    assert Path.wildcard(Path.join(cache_root, "*")) == []
  end

  test "a cache that cannot be written is an error", %{tmp_dir: tmp_dir} do
    escript = escript(tmp_dir, @with_priv)
    not_a_directory = Path.join(tmp_dir, "cache")
    File.write!(not_a_directory, "")

    assert {:error, message} = Localize.Priv.extract(escript, not_a_directory)
    assert message =~ "Cannot write Localize's data"
  end

  test "a record that cannot be written costs only a later start", %{tmp_dir: tmp_dir} do
    escript = escript(tmp_dir, @with_priv)
    cache_root = Path.join(tmp_dir, "cache")

    assert {:ok, priv} = Localize.Priv.extract(escript, cache_root)
    [record] = Path.wildcard(Path.join(cache_root, "escript-*"))
    File.rm!(record)
    File.mkdir_p!(Path.join(record, "occupied"))

    build(escript, [{~c"escript_probe/ebin/escript_probe.beam", "changed code"} | @with_priv])

    assert {:ok, ^priv} = Localize.Priv.extract(escript, cache_root)
    assert Path.wildcard(Path.join(cache_root, "escript-*")) == [record]
  end

  test "an escript without Localize's data says to include it", %{tmp_dir: tmp_dir} do
    escript = escript(tmp_dir, [{~c"localize/ebin/localize.app", "{application, localize, []}."}])

    assert {:error, message} = Localize.Priv.extract(escript, Path.join(tmp_dir, "cache"))
    assert message =~ "include_priv_for: [:localize]"
    assert Path.wildcard(Path.join([tmp_dir, "cache", "*"])) == []
  end

  test "a missing or unreadable escript is an error", %{tmp_dir: tmp_dir} do
    assert {:error, _message} =
             Localize.Priv.extract(Path.join(tmp_dir, "absent"), Path.join(tmp_dir, "cache"))

    not_an_escript = Path.join(tmp_dir, "plain")
    File.write!(not_an_escript, "not an escript")

    assert {:error, _message} = Localize.Priv.extract(not_an_escript, Path.join(tmp_dir, "cache"))

    source_only = Path.join(tmp_dir, "source_only")

    :ok =
      :escript.create(String.to_charlist(source_only), [:shebang, {:source, "main(_) -> ok."}])

    assert {:error, message} = Localize.Priv.extract(source_only, Path.join(tmp_dir, "cache"))
    assert message =~ "has no archive"
  end

  test "finds the escript enclosing a path inside its archive", %{tmp_dir: tmp_dir} do
    escript = escript(tmp_dir, @with_priv)

    assert Localize.Priv.enclosing_file(Path.join([escript, "localize", "priv"])) == escript
    assert Localize.Priv.enclosing_file(Path.join([tmp_dir, "absent", "priv"])) == nil
    assert Localize.Priv.enclosing_file(tmp_dir) == nil
  end

  test "outside an escript the directory is the application's own" do
    assert Localize.Priv.dir() == Application.app_dir(:localize, "priv")

    assert Localize.Priv.path("localize/version") ==
             Application.app_dir(:localize, "priv/localize/version")
  end

  test "outside an escript the user cache directory is never consulted" do
    cache_root = fn -> flunk("the user cache directory was consulted") end

    assert Localize.Priv.locate(cache_root) == {:ok, Application.app_dir(:localize, "priv")}
  end

  # `:filename.basedir/2` raises when `HOME` is unset, as it is for many
  # service accounts, so this runs in a VM started without it.
  test "without HOME Localize still starts, and an escript's cache is an error" do
    erl = Path.join([:code.root_dir(), "bin", "erl"])
    paths = Enum.flat_map([:elixir, :localize], &["-pa", Application.app_dir(&1, "ebin")])

    probe =
      ~s|Results = {'Elixir.Localize.Priv':prepare(), 'Elixir.Localize.Priv':cache_root()}, | <>
        ~s|io:format("~s~n", [base64:encode(term_to_binary(Results))]), halt().|

    {output, 0} =
      System.cmd(erl, ["-noshell" | paths] ++ ["-eval", probe],
        env: [{"HOME", nil}, {"XDG_CACHE_HOME", nil}]
      )

    {prepared, cache_root} =
      output
      |> String.split("\n", trim: true)
      |> List.last()
      |> Base.decode64!()
      |> :erlang.binary_to_term([:safe])

    assert prepared == {:ok, Application.app_dir(:localize, "priv")}
    assert {:error, message} = cache_root
    assert message =~ "HOME"
  end
end
