# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule ObjectStore do
  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts) do
    dir = Keyword.fetch!(opts, :dir)

    case Keyword.fetch(opts, :name) do
      {:ok, name} -> GenServer.start_link(__MODULE__, dir, name: name)
      :error -> GenServer.start_link(__MODULE__, dir)
    end
  end

  def store(server, content) do
    GenServer.call(server, {:store, IO.iodata_to_binary(content)})
  end

  def retrieve(server, hash) do
    GenServer.call(server, {:retrieve, hash})
  end

  def has_object?(server, hash) do
    GenServer.call(server, {:has_object?, hash})
  end

  def list_objects(server) do
    GenServer.call(server, :list_objects)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(dir) do
    case File.mkdir_p(dir) do
      :ok -> {:ok, %{dir: dir}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:store, content}, _from, state) do
    hash = hash_hex(content)
    path = object_path(state.dir, hash)

    result =
      if File.exists?(path) do
        {:ok, hash}
      else
        write_object(path, content, hash)
      end

    {:reply, result, state}
  end

  def handle_call({:retrieve, hash}, _from, state) do
    path = object_path(state.dir, hash)

    result =
      case File.read(path) do
        {:ok, compressed} -> decode_and_verify(compressed, hash)
        {:error, :enoent} -> {:error, :not_found}
        {:error, _reason} -> {:error, :corrupt}
      end

    {:reply, result, state}
  end

  def handle_call({:has_object?, hash}, _from, state) do
    {:reply, File.exists?(object_path(state.dir, hash)), state}
  end

  def handle_call(:list_objects, _from, state) do
    {:reply, scan_objects(state.dir), state}
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp hash_hex(content) do
    :sha
    |> :crypto.hash(content)
    |> Base.encode16(case: :lower)
  end

  defp object_path(dir, hash) do
    <<prefix::binary-size(2), rest::binary>> = hash
    Path.join([dir, prefix, rest])
  end

  defp write_object(path, content, hash) do
    compressed = :zlib.compress(content)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, compressed) do
      {:ok, hash}
    end
  end

  defp decode_and_verify(compressed, hash) do
    content = :zlib.uncompress(compressed)

    if hash_hex(content) == hash do
      {:ok, content}
    else
      {:error, :corrupt}
    end
  rescue
    _error -> {:error, :corrupt}
  catch
    _kind, _reason -> {:error, :corrupt}
  end

  defp scan_objects(dir) do
    dir
    |> subdirs()
    |> Enum.flat_map(fn prefix ->
      dir
      |> Path.join(prefix)
      |> files()
      |> Enum.map(&(prefix <> &1))
    end)
    |> Enum.sort()
  end

  defp subdirs(dir) do
    dir
    |> list_dir()
    |> Enum.filter(fn entry ->
      String.length(entry) == 2 and File.dir?(Path.join(dir, entry))
    end)
  end

  defp files(dir) do
    dir
    |> list_dir()
    |> Enum.filter(fn entry ->
      String.length(entry) == 38 and File.regular?(Path.join(dir, entry))
    end)
  end

  defp list_dir(dir) do
    case File.ls(dir) do
      {:ok, entries} -> entries
      {:error, _reason} -> []
    end
  end
end
```
