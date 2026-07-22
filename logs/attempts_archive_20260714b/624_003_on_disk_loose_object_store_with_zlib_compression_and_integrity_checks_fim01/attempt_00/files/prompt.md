# Task: Implement `decode_and_verify/2`

You are given the complete `ObjectStore` module below — a content-addressable
object store that persists zlib-compressed "loose object" files to disk and
verifies their integrity on read. Every function is fully implemented **except**
the private helper `decode_and_verify/2`, whose body has been replaced with
`# TODO`.

Implement the private `decode_and_verify/2` function. It receives the raw
`compressed` bytes read from an object file and the `hash` (lowercase hex SHA-1)
under which the caller requested the object. It must decompress the bytes with
`:zlib.uncompress/1`, then recompute the lowercase hex SHA-1 of the decompressed
content using the existing `hash_hex/1` helper. If that recomputed hash equals
the requested `hash`, return `{:ok, content}` with the decompressed bytes.
Otherwise return `{:error, :corrupt}`. Decompression can fail on malformed input
by raising an exception or throwing — treat any such failure (via `rescue` and
`catch`) as `{:error, :corrupt}` as well, so this function never crashes the
GenServer regardless of what bytes are on disk.

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

  defp decode_and_verify(compressed, hash) do
    # TODO
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