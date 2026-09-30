defmodule Localize.Priv do
  @moduledoc false

  # Localize reads its data from its `priv` directory at runtime. Inside an
  # escript the application's directory is a path within the escript's
  # archive, which no `File` function can read: the escript is a file, not
  # a directory, so each read fails with `:enotdir`. Mix leaves a
  # dependency's `priv` out of an escript unless it is built with
  # `include_priv_for: [:localize]`, and names `:escript.extract/2` as the
  # way to reach it. So in an escript the archive's copy of `priv` is
  # extracted into the user cache directory and read from there, where the
  # locale cache is writable too.
  #
  # The copy is named for the data it holds, so every build of every
  # escript carrying the same Localize data shares one copy, and the
  # locales downloaded into it, rather than each rebuild leaving another
  # behind. Naming the copy means inflating the data, so a small file named
  # for the escript's path records which copy the escript's current build
  # uses: while the escript's size and modification time are unchanged, a
  # start reads that file and not the archive.

  @dir_key {__MODULE__, :dir}
  @priv_prefix ~c"localize/priv/"

  @doc """
  Returns the path of an entry under Localize's `priv` directory.

  ### Arguments

  * `relative` is the entry's path relative to `priv`, such as
    `"localize/version"`.

  ### Returns

  * The absolute path.

  """
  @spec path(Path.t()) :: String.t()
  def path(relative), do: Path.join(dir(), relative)

  @doc """
  Returns Localize's `priv` directory: the application's own, or the copy
  extracted from the escript Localize runs in.

  ### Returns

  * The directory's absolute path.

  """
  @spec dir() :: String.t()
  def dir do
    case :persistent_term.get(@dir_key, nil) do
      nil ->
        case locate() do
          {:ok, dir} -> remember(dir)
          {:error, _message} -> remember(Application.app_dir(:localize, "priv"))
        end

      dir ->
        dir
    end
  end

  @doc """
  Makes Localize's `priv` directory readable before the application starts,
  extracting it from the escript Localize runs in when there is one.

  ### Returns

  * `{:ok, dir}` with the directory's absolute path.

  * `{:error, message}` when Localize runs in an escript whose archive does
    not hold Localize's `priv` directory, or it cannot be extracted.

  """
  @spec prepare() :: {:ok, String.t()} | {:error, String.t()}
  def prepare do
    with {:ok, dir} <- locate() do
      {:ok, remember(dir)}
    end
  end

  @doc false
  # The directory for the application's `priv` path, extracting it from an
  # enclosing escript when the path lies inside one. `cache_root` is called
  # only then, so outside an escript neither the user cache directory nor
  # the environment variables that locate it play any part.
  @spec locate((-> {:ok, String.t()} | {:error, String.t()})) ::
          {:ok, String.t()} | {:error, String.t()}
  def locate(cache_root \\ &cache_root/0) do
    priv = Application.app_dir(:localize, "priv")

    cond do
      File.dir?(priv) ->
        {:ok, priv}

      escript = enclosing_file(priv) ->
        with {:ok, root} <- cache_root.(), do: extract(escript, root)

      true ->
        {:ok, priv}
    end
  end

  @doc false
  # The user cache directory that Localize's data is extracted into.
  # `:filename.basedir/2` raises when the environment does not locate it:
  # on Unix, when `HOME` is unset.
  @spec cache_root() :: {:ok, String.t()} | {:error, String.t()}
  def cache_root do
    case Localize.Utils.Helpers.run_isolated(fn -> :filename.basedir(:user_cache, "localize") end) do
      {:ok, root} ->
        {:ok, root}

      {:error, _exception} ->
        {:error,
         "Localize runs in an escript and extracts its data into the user cache directory, " <>
           "which cannot be located: set the HOME environment variable."}
    end
  end

  @doc false
  # The nearest existing ancestor of `path` when it is a regular file: the
  # escript whose archive holds `path`.
  @spec enclosing_file(Path.t()) :: String.t() | nil
  def enclosing_file(path) do
    parent = Path.dirname(path)

    cond do
      parent == path -> nil
      File.regular?(parent) -> parent
      File.exists?(parent) -> nil
      true -> enclosing_file(parent)
    end
  end

  @doc false
  # Returns the copy under `cache_root` of the `localize/priv` entries of
  # an escript's archive, extracting them when no copy of the same data is
  # there yet.
  @spec extract(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def extract(escript, cache_root) do
    with {:ok, build} <- build(escript) do
      record = Path.join(cache_root, "escript-" <> digest(escript))

      case recorded(record, build, cache_root) do
        {:ok, data} -> {:ok, data}
        :none -> extract_data(escript, cache_root, record, build)
      end
    end
  end

  # An escript's build, identified by its size and modification time:
  # building an escript writes the whole file. Modification times are in
  # whole seconds, so two builds of one size written within the same
  # second are taken for one.
  defp build(escript) do
    case File.stat(escript, time: :posix) do
      {:ok, %File.Stat{size: size, mtime: mtime}} ->
        {:ok, "#{size}-#{mtime}"}

      {:error, reason} ->
        {:error, "Cannot read the escript #{escript}: #{:file.format_error(reason)}"}
    end
  end

  # The copy recorded for this build of the escript, when it still exists.
  # A record that is not one this module wrote is ignored.
  defp recorded(record, build, cache_root) do
    with {:ok, contents} <- File.read(record),
         [^build, key] <- String.split(contents, " "),
         true <- key =~ ~r/\A[0-9a-f]{32}\z/,
         data = data_dir(cache_root, key),
         true <- File.dir?(data) do
      {:ok, data}
    else
      _other -> :none
    end
  end

  defp extract_data(escript, cache_root, record, build) do
    with {:ok, archive} <- archive(escript),
         {:ok, files} <- priv_files(escript, archive) do
      key = content_key(files)
      data = data_dir(cache_root, key)

      with :ok <- write_data(files, data) do
        _recorded = write_record(record, build, key)
        {:ok, data}
      end
    end
  end

  defp archive(escript) do
    case :escript.extract(String.to_charlist(escript), []) do
      {:ok, sections} ->
        case Keyword.get(sections, :archive) do
          archive when is_binary(archive) -> {:ok, archive}
          _none -> {:error, "The escript #{escript} has no archive to read Localize's data from."}
        end

      {:error, reason} ->
        {:error, "Cannot read the escript #{escript}: #{inspect(reason)}"}
    end
  end

  # The archive's `localize/priv` files, as paths relative to `priv` with
  # their contents.
  defp priv_files(escript, archive) do
    case :zip.extract(archive, [:memory, file_filter: &priv_entry?/1]) do
      {:ok, []} ->
        {:error,
         "Localize runs in the escript #{escript}, which does not hold Localize's data. " <>
           "Build the escript with `include_priv_for: [:localize]` in its `escript` configuration."}

      {:ok, entries} ->
        relative_files(escript, entries)

      {:error, reason} ->
        {:error, "Cannot extract Localize's data from the escript #{escript}: #{inspect(reason)}"}
    end
  end

  defp priv_entry?({:zip_file, name, info, _comment, _offset, _size}) do
    elem(info, 2) == :regular and :lists.prefix(@priv_prefix, name)
  end

  defp relative_files(escript, entries) do
    Enum.reduce_while(entries, {:ok, []}, fn {name, content}, {:ok, files} ->
      case relative(name) do
        {:ok, relative} ->
          {:cont, {:ok, [{relative, content} | files]}}

        :error ->
          {:halt,
           {:error,
            "The escript #{escript} holds a file outside Localize's data: #{inspect(name)}"}}
      end
    end)
  end

  # Checked by its segments alone: `Path.safe_relative/1` would consult
  # symbolic links under the current directory, which has nothing to do
  # with where the file is written.
  defp relative(name) do
    case :unicode.characters_to_binary(Enum.drop(name, length(@priv_prefix))) do
      relative when is_binary(relative) and relative != "" ->
        if Path.type(relative) == :relative and ".." not in Path.split(relative),
          do: {:ok, relative},
          else: :error

      _other ->
        :error
    end
  end

  # Names a copy for the data it holds: each file's path and contents.
  defp content_key(files) do
    files
    |> Enum.sort()
    |> Enum.map(fn {relative, content} ->
      [<<byte_size(relative)::32>>, relative, <<byte_size(content)::64>>, content]
    end)
    |> :erlang.md5()
    |> Base.encode16(case: :lower)
  end

  defp digest(escript), do: escript |> :erlang.md5() |> Base.encode16(case: :lower)

  defp data_dir(cache_root, key), do: Path.join(cache_root, "data-" <> key)

  # The copy is written into a temporary directory that is renamed into
  # place, so a concurrent start never reads a partial copy.
  defp write_data(files, data) do
    if File.dir?(data) do
      :ok
    else
      temporary = "#{data}.#{System.unique_integer([:positive])}"
      result = with :ok <- write_files(files, temporary), do: rename(temporary, data)
      _removed = File.rm_rf(temporary)
      result
    end
  end

  defp write_files(files, directory) do
    Enum.reduce_while(files, :ok, fn {relative, content}, :ok ->
      case write_file(Path.join(directory, relative), content) do
        :ok ->
          {:cont, :ok}

        {:error, reason} ->
          {:halt,
           {:error,
            "Cannot write Localize's data into #{directory}: #{:file.format_error(reason)}"}}
      end
    end)
  end

  defp write_file(file, content) do
    with :ok <- File.mkdir_p(Path.dirname(file)) do
      File.write(file, content)
    end
  end

  # Another process may have written the same copy in the meantime; its
  # copy is as good as this one.
  defp rename(temporary, data) do
    case File.rename(temporary, data) do
      :ok ->
        :ok

      {:error, _reason} ->
        if File.dir?(data),
          do: :ok,
          else: {:error, "Cannot write Localize's data into #{data}"}
    end
  end

  # The record is written to a temporary file renamed into place, so a
  # concurrent start reads the old record or the new one, never part of
  # one. Failing to write it costs only the next start reading the archive
  # again.
  defp write_record(record, build, key) do
    temporary = "#{record}.#{System.unique_integer([:positive])}"

    with :ok <- File.write(temporary, "#{build} #{key}"),
         :ok <- File.rename(temporary, record) do
      :ok
    else
      {:error, _reason} = error ->
        _removed = File.rm(temporary)
        error
    end
  end

  defp remember(dir) do
    :persistent_term.put(@dir_key, dir)
    dir
  end
end
