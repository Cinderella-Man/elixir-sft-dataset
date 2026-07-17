# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule ObjectStore do
  @moduledoc """
  A content-addressable object store that persists objects to disk as
  compressed "loose object" files, in the style of Git's `.git/objects`
  directory.

  Objects are addressed by the lowercase hex SHA-1 hash of their raw
  content. Each object is stored zlib-compressed at the path
  `<dir>/<first 2 hash chars>/<remaining 38 hash chars>`.

  The process keeps **no in-memory copy** of object contents — every read
  and write goes to the filesystem. Consequently, two processes pointed at
  the same directory see the same objects, and objects survive process
  restarts. Integrity is verified on every read: the decompressed bytes
  must hash back to the requested address.
  """

  use GenServer

  @typedoc "Lowercase hex-encoded SHA-1 hash."
  @type hash :: String.t()

  @typedoc "A running `ObjectStore` server reference."
  @type server :: GenServer.server()

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the object store process.

  Options:

    * `:dir` (required) — the directory in which objects are stored. It is
      created on startup if it does not already exist.
    * `:name` (optional) — a name under which to register the process.

  Returns `{:ok, pid}` on success or `{:error, reason}` on failure.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    dir = Keyword.fetch!(opts, :dir)

    case Keyword.fetch(opts, :name) do
      {:ok, name} -> GenServer.start_link(__MODULE__, dir, name: name)
      :error -> GenServer.start_link(__MODULE__, dir)
    end
  end

  @doc """
  Stores `content` and returns `{:ok, hash}`.

  The SHA-1 hash of `content` is computed, and the zlib-compressed bytes are
  written to the object's path on disk. The operation is idempotent: storing
  the same content twice yields the same hash and does not rewrite an
  existing file.
  """
  @spec store(server(), iodata()) :: {:ok, hash()} | {:error, term()}
  def store(server, content) do
    GenServer.call(server, {:store, IO.iodata_to_binary(content)})
  end

  @doc """
  Retrieves the content stored under `hash`.

  Returns `{:ok, content}` on success, `{:error, :not_found}` if no object
  file exists for `hash`, or `{:error, :corrupt}` if the file cannot be
  decompressed or its contents do not hash back to `hash`.
  """
  @spec retrieve(server(), hash()) ::
          {:ok, binary()} | {:error, :not_found} | {:error, :corrupt}
  def retrieve(server, hash) do
    GenServer.call(server, {:retrieve, hash})
  end

  @doc """
  Returns `true` if an object file exists for `hash`, `false` otherwise.
  """
  @spec has_object?(server(), hash()) :: boolean()
  def has_object?(server, hash) do
    GenServer.call(server, {:has_object?, hash})
  end

  @doc """
  Returns a sorted list of the hex SHA-1 hashes of every object on disk.
  """
  @spec list_objects(server()) :: [hash()]
  def list_objects(server) do
    GenServer.call(server, :list_objects)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  @spec init(String.t()) :: {:ok, %{dir: String.t()}} | {:stop, term()}
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

  @spec hash_hex(binary()) :: hash()
  defp hash_hex(content) do
    :sha
    |> :crypto.hash(content)
    |> Base.encode16(case: :lower)
  end

  @spec object_path(String.t(), hash()) :: String.t()
  defp object_path(dir, hash) do
    <<prefix::binary-size(2), rest::binary>> = hash
    Path.join([dir, prefix, rest])
  end

  @spec write_object(String.t(), binary(), hash()) :: {:ok, hash()} | {:error, term()}
  defp write_object(path, content, hash) do
    compressed = :zlib.compress(content)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, compressed) do
      {:ok, hash}
    end
  end

  @spec decode_and_verify(binary(), hash()) :: {:ok, binary()} | {:error, :corrupt}
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

  @spec scan_objects(String.t()) :: [hash()]
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

  @spec subdirs(String.t()) :: [String.t()]
  defp subdirs(dir) do
    dir
    |> list_dir()
    |> Enum.filter(fn entry ->
      String.length(entry) == 2 and File.dir?(Path.join(dir, entry))
    end)
  end

  @spec files(String.t()) :: [String.t()]
  defp files(dir) do
    dir
    |> list_dir()
    |> Enum.filter(fn entry ->
      String.length(entry) == 38 and File.regular?(Path.join(dir, entry))
    end)
  end

  @spec list_dir(String.t()) :: [String.t()]
  defp list_dir(dir) do
    case File.ls(dir) do
      {:ok, entries} -> entries
      {:error, _reason} -> []
    end
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule ObjectStoreTest do
  use ExUnit.Case, async: false

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "objstore_#{System.pid()}_#{System.unique_integer([:positive])}"
      )

    {:ok, s} = ObjectStore.start_link(dir: dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{store: s, dir: dir}
  end

  defp sha1(content), do: :crypto.hash(:sha, content) |> Base.encode16(case: :lower)

  defp object_path(dir, hash) do
    Path.join([dir, String.slice(hash, 0, 2), String.slice(hash, 2, 38)])
  end

  # ---------------- basic store / retrieve ----------------

  test "store returns the lowercase SHA-1 hash", %{store: s} do
    {:ok, hash} = ObjectStore.store(s, "hello world")
    assert hash == sha1("hello world")
    assert hash =~ ~r/^[0-9a-f]{40}$/
  end

  test "retrieve returns the stored content", %{store: s} do
    {:ok, hash} = ObjectStore.store(s, "round trip")
    assert {:ok, "round trip"} = ObjectStore.retrieve(s, hash)
  end

  test "retrieve returns not_found for unknown hash", %{store: s} do
    assert {:error, :not_found} =
             ObjectStore.retrieve(s, "0000000000000000000000000000000000000000")
  end

  test "store is idempotent", %{store: s} do
    {:ok, h1} = ObjectStore.store(s, "dup")
    {:ok, h2} = ObjectStore.store(s, "dup")
    assert h1 == h2
  end

  test "empty and null-byte content round-trip", %{store: s} do
    {:ok, he} = ObjectStore.store(s, "")
    assert {:ok, ""} = ObjectStore.retrieve(s, he)

    bin = <<0, 1, 2, 255, 254, 253>>
    {:ok, hb} = ObjectStore.store(s, bin)
    assert {:ok, ^bin} = ObjectStore.retrieve(s, hb)
  end

  # ---------------- on-disk layout ----------------

  test "object is written at the documented fan-out path", %{store: s, dir: dir} do
    {:ok, hash} = ObjectStore.store(s, "layout check")
    assert File.exists?(object_path(dir, hash))
  end

  test "the file contents are zlib-compressed raw bytes", %{store: s, dir: dir} do
    content = "compress me please"
    {:ok, hash} = ObjectStore.store(s, content)
    raw = File.read!(object_path(dir, hash))
    assert :zlib.uncompress(raw) == content
  end

  # ---------------- integrity checks ----------------

  test "retrieve returns corrupt when the file cannot be decompressed", %{store: s, dir: dir} do
    {:ok, hash} = ObjectStore.store(s, "will be clobbered")
    File.write!(object_path(dir, hash), "this is not valid zlib data")
    assert {:error, :corrupt} = ObjectStore.retrieve(s, hash)
  end

  test "retrieve returns corrupt when the hash does not match", %{store: s, dir: dir} do
    # TODO
  end

  # ---------------- has_object? / list_objects ----------------

  test "has_object? reflects presence", %{store: s} do
    {:ok, hash} = ObjectStore.store(s, "present")
    assert ObjectStore.has_object?(s, hash) == true
    assert ObjectStore.has_object?(s, sha1("absent")) == false
  end

  test "list_objects returns all hashes sorted", %{store: s} do
    {:ok, h1} = ObjectStore.store(s, "one")
    {:ok, h2} = ObjectStore.store(s, "two")
    {:ok, h3} = ObjectStore.store(s, "three")
    assert ObjectStore.list_objects(s) == Enum.sort([h1, h2, h3])
  end

  # ---------------- persistence across processes ----------------

  test "objects persist to a new process using the same directory", %{store: s, dir: dir} do
    {:ok, h1} = ObjectStore.store(s, "persist one")
    {:ok, h2} = ObjectStore.store(s, "persist two")
    :ok = GenServer.stop(s)

    {:ok, s2} = ObjectStore.start_link(dir: dir)
    assert {:ok, "persist one"} = ObjectStore.retrieve(s2, h1)
    assert {:ok, "persist two"} = ObjectStore.retrieve(s2, h2)
    assert ObjectStore.list_objects(s2) == Enum.sort([h1, h2])
  end

  test "a second live process on the same directory sees objects written by the first", %{
    store: s,
    dir: dir
  } do
    {:ok, s2} = ObjectStore.start_link(dir: dir)

    {:ok, h1} = ObjectStore.store(s, "written by first")
    assert {:ok, "written by first"} = ObjectStore.retrieve(s2, h1)
    assert ObjectStore.has_object?(s2, h1) == true

    {:ok, h2} = ObjectStore.store(s2, "written by second")
    assert {:ok, "written by second"} = ObjectStore.retrieve(s, h2)
    assert ObjectStore.list_objects(s) == Enum.sort([h1, h2])

    :ok = GenServer.stop(s2)
  end

  test "storing the same content twice leaves the existing file untouched", %{store: s, dir: dir} do
    content = "no rewrite please"
    {:ok, hash} = ObjectStore.store(s, content)
    path = object_path(dir, hash)

    stamp = 946_684_800
    :ok = File.touch!(path, stamp)
    assert File.stat!(path, time: :posix).mtime == stamp

    {:ok, ^hash} = ObjectStore.store(s, content)

    assert File.stat!(path, time: :posix).mtime == stamp
    assert {:ok, ^content} = ObjectStore.retrieve(s, hash)
  end

  test "start_link creates the object directory when it does not exist", %{dir: dir} do
    nested = Path.join([dir, "not", "yet", "created"])
    refute File.exists?(nested)

    {:ok, s2} = ObjectStore.start_link(dir: nested)
    assert File.dir?(nested)

    {:ok, hash} = ObjectStore.store(s2, "fresh dir")
    assert File.exists?(object_path(nested, hash))
    assert ObjectStore.list_objects(s2) == [hash]

    :ok = GenServer.stop(s2)
  end

  test "start_link registers the process under the given :name", %{dir: dir} do
    name = :"objstore_named_#{System.unique_integer([:positive])}"
    {:ok, pid} = ObjectStore.start_link(dir: Path.join(dir, "named"), name: name)
    assert Process.whereis(name) == pid

    {:ok, hash} = ObjectStore.store(name, "via name")
    assert {:ok, "via name"} = ObjectStore.retrieve(name, hash)
    assert ObjectStore.has_object?(name, hash) == true
    assert ObjectStore.list_objects(name) == [hash]

    :ok = GenServer.stop(name)
  end

  test "list_objects returns an empty list for a store with no objects", %{store: s} do
    assert ObjectStore.list_objects(s) == []

    {:ok, hash} = ObjectStore.store(s, "only one")
    assert ObjectStore.list_objects(s) == [hash]
  end

  test "start_link without the required :dir option raises" do
    assert_raise KeyError, fn -> ObjectStore.start_link([]) end
    assert_raise KeyError, fn -> ObjectStore.start_link(name: :objstore_no_dir) end
  end
end
```
