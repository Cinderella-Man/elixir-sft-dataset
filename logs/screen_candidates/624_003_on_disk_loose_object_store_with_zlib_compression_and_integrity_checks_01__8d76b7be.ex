defmodule ObjectStore do
  @moduledoc """
  A content-addressable object store that persists objects to disk as compressed
  "loose object" files, in the style of Git's `.git/objects` directory.

  Every object is identified by the lowercase hex SHA-1 of its raw content. The
  object with hash `H` is written to:

      <dir>/<first two chars of H>/<remaining 38 chars of H>

  The file body is the zlib-compressed raw content (`:zlib.compress/1`).

  The GenServer holds **no in-memory copy** of any object content: its state is
  only the directory path. Every read and write goes to the filesystem. As a
  consequence:

    * two processes pointed at the same directory observe the same objects;
    * objects survive process restarts;
    * storing identical content twice is idempotent and does not rewrite the file.

  Reads verify integrity: the file is decompressed and re-hashed, and a mismatch
  (or a zlib failure) is reported as `{:error, :corrupt}`.

  ## Example

      {:ok, store} = ObjectStore.start_link(dir: "/tmp/objects")
      {:ok, hash} = ObjectStore.store(store, "hello world")
      {:ok, "hello world"} = ObjectStore.retrieve(store, hash)
      true = ObjectStore.has_object?(store, hash)
      [^hash] = ObjectStore.list_objects(store)
  """

  use GenServer

  @typedoc "Lowercase hex-encoded SHA-1 digest (40 characters)."
  @type hash :: String.t()

  @typedoc "A reference to a running `ObjectStore` process."
  @type server :: GenServer.server()

  # ----------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------

  @doc """
  Starts the object store.

  ## Options

    * `:dir` - (required) directory in which loose objects are stored. It is
      created, together with any missing parent directories, if it does not exist.
    * `:name` - (optional) name under which the process is registered.

  Returns `{:ok, pid}` on success, or `{:error, reason}` if the directory could
  not be created.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    dir = Keyword.fetch!(opts, :dir)
    {name, _rest} = Keyword.pop(opts, :name)

    case name do
      nil -> GenServer.start_link(__MODULE__, dir)
      name -> GenServer.start_link(__MODULE__, dir, name: name)
    end
  end

  @doc """
  Stores `content` and returns `{:ok, hash}` where `hash` is the lowercase hex
  SHA-1 of `content`.

  The operation is idempotent: storing the same content twice yields the same
  hash and leaves an already-existing object file untouched.

  Returns `{:error, reason}` (a POSIX error atom) if the object could not be
  written.
  """
  @spec store(server(), binary()) :: {:ok, hash()} | {:error, term()}
  def store(server, content) when is_binary(content) do
    GenServer.call(server, {:store, content})
  end

  @doc """
  Retrieves the content stored under `hash`.

  Returns:

    * `{:ok, content}` when the object exists and its SHA-1 matches `hash`;
    * `{:error, :not_found}` when no object file exists for `hash`;
    * `{:error, :corrupt}` when the file cannot be decompressed or the SHA-1 of
      the decompressed bytes differs from `hash`.
  """
  @spec retrieve(server(), hash()) :: {:ok, binary()} | {:error, :not_found | :corrupt}
  def retrieve(server, hash) when is_binary(hash) do
    GenServer.call(server, {:retrieve, hash})
  end

  @doc """
  Returns `true` if an object file exists on disk for `hash`, `false` otherwise.

  This only checks for the presence of the file; it does not verify its contents.
  """
  @spec has_object?(server(), hash()) :: boolean()
  def has_object?(server, hash) when is_binary(hash) do
    GenServer.call(server, {:has_object?, hash})
  end

  @doc """
  Returns the sorted list of lowercase hex SHA-1 hashes of every object currently
  present on disk.
  """
  @spec list_objects(server()) :: [hash()]
  def list_objects(server) do
    GenServer.call(server, :list_objects)
  end

  # ----------------------------------------------------------------------------
  # GenServer callbacks
  # ----------------------------------------------------------------------------

  @impl GenServer
  def init(dir) when is_binary(dir) do
    case File.mkdir_p(dir) do
      :ok -> {:ok, %{dir: dir}}
      {:error, reason} -> {:stop, {:cannot_create_dir, dir, reason}}
    end
  end

  @impl GenServer
  def handle_call({:store, content}, _from, %{dir: dir} = state) do
    hash = hash_content(content)
    path = object_path(dir, hash)

    if File.exists?(path) do
      {:reply, {:ok, hash}, state}
    else
      {:reply, write_object(path, content, hash), state}
    end
  end

  def handle_call({:retrieve, hash}, _from, %{dir: dir} = state) do
    reply =
      case valid_hash_path(dir, hash) do
        {:ok, path} -> read_object(path, hash)
        :error -> {:error, :not_found}
      end

    {:reply, reply, state}
  end

  def handle_call({:has_object?, hash}, _from, %{dir: dir} = state) do
    reply =
      case valid_hash_path(dir, hash) do
        {:ok, path} -> File.regular?(path)
        :error -> false
      end

    {:reply, reply, state}
  end

  def handle_call(:list_objects, _from, %{dir: dir} = state) do
    {:reply, scan_objects(dir), state}
  end

  # ----------------------------------------------------------------------------
  # Internal helpers
  # ----------------------------------------------------------------------------

  @spec hash_content(binary()) :: hash()
  defp hash_content(content) do
    :sha
    |> :crypto.hash(content)
    |> Base.encode16(case: :lower)
  end

  @spec object_path(String.t(), hash()) :: Path.t()
  defp object_path(dir, hash) do
    <<prefix::binary-size(2), rest::binary>> = hash
    Path.join([dir, prefix, rest])
  end

  # Returns the on-disk path only for syntactically valid 40-char hex hashes;
  # anything else can never name an object and is reported as absent.
  @spec valid_hash_path(String.t(), binary()) :: {:ok, Path.t()} | :error
  defp valid_hash_path(dir, hash) do
    if valid_hash?(hash) do
      {:ok, object_path(dir, hash)}
    else
      :error
    end
  end

  @spec valid_hash?(binary()) :: boolean()
  defp valid_hash?(hash) do
    byte_size(hash) == 40 and
      Enum.all?(String.to_charlist(hash), fn c ->
        c in ?0..?9 or c in ?a..?f
      end)
  end

  @spec write_object(Path.t(), binary(), hash()) :: {:ok, hash()} | {:error, term()}
  defp write_object(path, content, hash) do
    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, :zlib.compress(content)) do
      {:ok, hash}
    end
  end

  @spec read_object(Path.t(), hash()) :: {:ok, binary()} | {:error, :not_found | :corrupt}
  defp read_object(path, hash) do
    case File.read(path) do
      {:ok, compressed} -> decompress_and_verify(compressed, hash)
      {:error, :enoent} -> {:error, :not_found}
      {:error, _reason} -> {:error, :corrupt}
    end
  end

  @spec decompress_and_verify(binary(), hash()) :: {:ok, binary()} | {:error, :corrupt}
  defp decompress_and_verify(compressed, hash) do
    content = :zlib.uncompress(compressed)

    if hash_content(content) == hash do
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
    |> list_dir()
    |> Enum.filter(&valid_prefix?(&1, dir))
    |> Enum.flat_map(fn prefix ->
      dir
      |> Path.join(prefix)
      |> list_dir()
      |> Enum.filter(&valid_suffix?/1)
      |> Enum.map(&(prefix <> &1))
    end)
    |> Enum.sort()
  end

  @spec list_dir(Path.t()) :: [String.t()]
  defp list_dir(path) do
    case File.ls(path) do
      {:ok, entries} -> entries
      {:error, _reason} -> []
    end
  end

  @spec valid_prefix?(String.t(), String.t()) :: boolean()
  defp valid_prefix?(entry, dir) do
    byte_size(entry) == 2 and hex?(entry) and File.dir?(Path.join(dir, entry))
  end

  @spec valid_suffix?(String.t()) :: boolean()
  defp valid_suffix?(entry) do
    byte_size(entry) == 38 and hex?(entry)
  end

  @spec hex?(binary()) :: boolean()
  defp hex?(binary) do
    Enum.all?(String.to_charlist(binary), fn c -> c in ?0..?9 or c in ?a..?f end)
  end
end