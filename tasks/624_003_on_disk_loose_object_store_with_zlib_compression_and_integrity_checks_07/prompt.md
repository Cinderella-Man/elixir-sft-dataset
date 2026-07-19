# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `retrieve` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir GenServer module called `ObjectStore` that implements a content-addressable object store which **persists objects to disk** as compressed "loose object" files (like Git's `.git/objects` directory) and **verifies integrity on read**. The store keeps no in-memory copy of object contents — every read and write goes to the filesystem — so a second process pointed at the same directory sees the same objects, and objects survive process restarts.

I need these functions in the public API:

- `ObjectStore.start_link(opts)` to start the process, returning `{:ok, pid}`. It accepts an optional `:name` option for process registration (when given, the process is registered under that atom, so `Process.whereis(name)` returns the pid and the name can be passed as `server` to every other function) and a **required** `:dir` option giving the directory in which objects are stored. Fetch `:dir` with `Keyword.fetch!/2` so that calling `start_link/1` without it raises `KeyError`. If the directory does not exist it must be created on startup, including any missing parent directories.

- `ObjectStore.store(server, content)` which takes an arbitrary binary/string, computes its SHA-1 hash (lowercase hex), writes the object to disk, and returns `{:ok, hash}`. Storing the same content twice must be idempotent — it returns the same hash and does not rewrite the file if it already exists (the existing file's mtime must be left untouched). Empty content and content with arbitrary bytes, including null bytes, must round-trip.

- `ObjectStore.retrieve(server, hash)` which reads the object file for `hash`, decompresses it, and returns `{:ok, content}` where `content` is the exact binary that was stored. If no file exists for that hash it returns `{:error, :not_found}`. If the file exists but cannot be decompressed, or the SHA-1 of the decompressed bytes does not equal the requested hash, it returns `{:error, :corrupt}` — a decompression failure must be caught rather than crashing the process.

- `ObjectStore.has_object?(server, hash)` which returns `true` if an object file exists for `hash`, `false` otherwise.

- `ObjectStore.list_objects(server)` which returns a sorted list of the SHA-1 hex hashes of every object currently present on disk, or `[]` when the store is empty. Because it scans the directory on each call, it must pick up objects written by another process pointed at the same directory.

On-disk layout (this is a fixed contract):
- The file path for an object with hash `H` is `<dir>/<first two characters of H>/<remaining 38 characters of H>`. That is, the object is stored in a two-character fan-out subdirectory named by the first two hex characters, in a file named by the remaining 38.
- The file contents are the **zlib-compressed** raw object bytes. Compress with `:zlib.compress/1` and decompress with `:zlib.uncompress/1`.

Implementation requirements:
- Use `:crypto.hash(:sha, content)` and `Base.encode16(hash, case: :lower)` for SHA-1 hashing.
- All object contents live on disk; there is no in-memory content map in the process state.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## The module with `retrieve` missing

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
    # TODO
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

Give me only the complete implementation of `retrieve` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
