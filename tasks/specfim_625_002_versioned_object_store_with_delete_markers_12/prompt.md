# Reconstruct the missing typespec

In the otherwise-complete module below, the `@spec` for
`valid_name?/1` has been removed; `# TODO: @spec` holds its place.
Write that one attribute — a `@spec` for `valid_name?/1` faithful to
the arguments, guards, and every return shape the code can actually
produce. Nothing else changes.

## The module with the `@spec` for `valid_name?/1` missing

```elixir
defmodule VersionedObjectStorage do
  @moduledoc """
  An S3-like, versioned object store backed by the local filesystem.

  Every `put_object/5` call creates a brand-new immutable version of a key and
  never destroys earlier versions, mirroring S3 bucket versioning. Deletes are
  *soft*: `delete_object/3` appends a special *delete marker* version that hides
  the object from `get_object/3` and `list_objects/2` while preserving all
  earlier versions. Individual versions (including delete markers) can be
  permanently removed with `delete_version/4`; removing the latest delete marker
  effectively restores the object.

  All state (buckets, versions, data, metadata, and delete markers) is persisted
  under a configurable `:root_dir` so that history survives a restart of the
  GenServer as long as the same directory is reused. One file per bucket is
  written using `:erlang.term_to_binary/1` for serialization.
  """

  use GenServer

  @type server :: GenServer.server()
  @type version_summary :: %{
          version_id: String.t(),
          is_delete_marker: boolean(),
          size: non_neg_integer(),
          last_modified: DateTime.t()
        }

  @default_root "./versioned_object_storage_data"
  @bucket_suffix ".bin"
  @name_regex ~r/^[a-z0-9.\-]+$/

  # ── Public API ──────────────────────────────────────────────────────────

  @doc """
  Start the storage process.

  Options:

    * `:root_dir` — base directory for all storage (default
      `#{inspect(@default_root)}`).
    * `:name` — optional name for process registration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Create a bucket named `name`.

  Returns `:ok`, `{:error, :already_exists}` if the bucket already exists, or
  `{:error, :invalid_name}` if the name is not a non-empty string of lowercase
  alphanumeric characters, hyphens, and dots.
  """
  @spec create_bucket(server(), String.t()) ::
          :ok | {:error, :already_exists | :invalid_name}
  def create_bucket(server, name) do
    GenServer.call(server, {:create_bucket, name})
  end

  @doc """
  Return `{:ok, buckets}` where `buckets` is a sorted list of bucket names.
  """
  @spec list_buckets(server()) :: {:ok, [String.t()]}
  def list_buckets(server) do
    GenServer.call(server, :list_buckets)
  end

  @doc """
  Store a new version of `key` in `bucket` with binary `data` and `metadata`.

  Each call creates a fresh version and never destroys earlier versions.
  Returns `{:ok, version_id}` or `{:error, :bucket_not_found}`.
  """
  @spec put_object(server(), String.t(), String.t(), binary(), map()) ::
          {:ok, String.t()} | {:error, :bucket_not_found}
  def put_object(server, bucket, key, data, metadata \\ %{}) do
    GenServer.call(server, {:put_object, bucket, key, data, metadata})
  end

  @doc """
  Retrieve the latest version of `key` in `bucket`.

  Returns `{:ok, object}` where `object` has `:data`, `:metadata`, `:size`,
  `:version_id`, and `:last_modified`. Returns `{:error, :bucket_not_found}` if
  the bucket is missing, or `{:error, :not_found}` if the key has no versions or
  its latest version is a delete marker.
  """
  @spec get_object(server(), String.t(), String.t()) ::
          {:ok, map()} | {:error, :bucket_not_found | :not_found}
  def get_object(server, bucket, key) do
    GenServer.call(server, {:get_object, bucket, key})
  end

  @doc """
  Retrieve one specific version of `key` in `bucket` by `version_id`.

  Returns `{:ok, object}` where `object` also includes `:is_delete_marker`. For
  a delete marker, `:data` is `""` and `:is_delete_marker` is `true`. Returns
  `{:error, :bucket_not_found}` or `{:error, :not_found}` on failure.
  """
  @spec get_object_version(server(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, :bucket_not_found | :not_found}
  def get_object_version(server, bucket, key, version_id) do
    GenServer.call(server, {:get_object_version, bucket, key, version_id})
  end

  @doc """
  Soft-delete `key` in `bucket` by appending a new delete marker version.

  The object is hidden from `get_object/3` and `list_objects/2` but all earlier
  versions are preserved. Returns `{:ok, version_id}` (the delete marker's id)
  or `{:error, :bucket_not_found}`.
  """
  @spec delete_object(server(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :bucket_not_found}
  def delete_object(server, bucket, key) do
    GenServer.call(server, {:delete_object, bucket, key})
  end

  @doc """
  List all versions of `key` in `bucket`, ordered newest first.

  Returns `{:ok, summaries}` where each summary has `:version_id`,
  `:is_delete_marker`, `:size`, and `:last_modified`. Returns `{:ok, []}` if the
  key has no versions, or `{:error, :bucket_not_found}`.
  """
  @spec list_versions(server(), String.t(), String.t()) ::
          {:ok, [version_summary()]} | {:error, :bucket_not_found}
  def list_versions(server, bucket, key) do
    GenServer.call(server, {:list_versions, bucket, key})
  end

  @doc """
  Permanently remove one specific version of `key` in `bucket` by `version_id`.

  Idempotent: succeeds even if the version does not exist. Removing the latest
  delete marker restores the object (the next-highest version becomes latest).
  Returns `:ok` or `{:error, :bucket_not_found}`.
  """
  @spec delete_version(server(), String.t(), String.t(), String.t()) ::
          :ok | {:error, :bucket_not_found}
  def delete_version(server, bucket, key, version_id) do
    GenServer.call(server, {:delete_version, bucket, key, version_id})
  end

  @doc """
  List the current state of `bucket`.

  Returns `{:ok, objects}` describing only keys whose latest version is a real
  object (not a delete marker), sorted lexicographically by key. Each entry has
  `:key`, `:size`, `:version_id`, and `:last_modified`. Returns
  `{:error, :bucket_not_found}`.
  """
  @spec list_objects(server(), String.t()) ::
          {:ok, [map()]} | {:error, :bucket_not_found}
  def list_objects(server, bucket) do
    GenServer.call(server, {:list_objects, bucket})
  end

  # ── GenServer callbacks ─────────────────────────────────────────────────

  @impl true
  def init(opts) do
    root = Keyword.get(opts, :root_dir, @default_root)
    File.mkdir_p!(root)
    {:ok, %{root_dir: root, buckets: load_buckets(root)}}
  end

  @impl true
  def handle_call({:create_bucket, name}, _from, state) do
    cond do
      not valid_name?(name) ->
        {:reply, {:error, :invalid_name}, state}

      Map.has_key?(state.buckets, name) ->
        {:reply, {:error, :already_exists}, state}

      true ->
        persist_bucket(state.root_dir, name, %{})
        {:reply, :ok, put_in(state.buckets[name], %{})}
    end
  end

  def handle_call(:list_buckets, _from, state) do
    {:reply, {:ok, state.buckets |> Map.keys() |> Enum.sort()}, state}
  end

  def handle_call({:put_object, bucket, key, data, metadata}, _from, state) do
    with_bucket(state, bucket, fn keys ->
      version = build_version(data, metadata, false)
      new_keys = prepend_version(keys, key, version)
      {{:ok, version.version_id}, new_keys}
    end)
  end

  def handle_call({:get_object, bucket, key}, _from, state) do
    reply =
      case fetch_bucket(state, bucket) do
        {:ok, keys} -> latest_object(keys, key)
        error -> error
      end

    {:reply, reply, state}
  end

  def handle_call({:get_object_version, bucket, key, version_id}, _from, state) do
    reply =
      case fetch_bucket(state, bucket) do
        {:ok, keys} -> fetch_version(keys, key, version_id)
        error -> error
      end

    {:reply, reply, state}
  end

  def handle_call({:delete_object, bucket, key}, _from, state) do
    with_bucket(state, bucket, fn keys ->
      version = build_version("", %{}, true)
      new_keys = prepend_version(keys, key, version)
      {{:ok, version.version_id}, new_keys}
    end)
  end

  def handle_call({:list_versions, bucket, key}, _from, state) do
    reply =
      case fetch_bucket(state, bucket) do
        {:ok, keys} -> {:ok, Enum.map(Map.get(keys, key, []), &summarize/1)}
        error -> error
      end

    {:reply, reply, state}
  end

  def handle_call({:delete_version, bucket, key, version_id}, _from, state) do
    with_bucket(state, bucket, fn keys ->
      versions = Map.get(keys, key, [])
      kept = Enum.reject(versions, &(&1.version_id == version_id))
      new_keys = update_key(keys, key, kept)
      {:ok, new_keys}
    end)
  end

  def handle_call({:list_objects, bucket}, _from, state) do
    reply =
      case fetch_bucket(state, bucket) do
        {:ok, keys} -> {:ok, current_objects(keys)}
        error -> error
      end

    {:reply, reply, state}
  end

  # ── Internal helpers ────────────────────────────────────────────────────

  # TODO: @spec
  defp valid_name?(name) when is_binary(name) and name != "" do
    Regex.match?(@name_regex, name)
  end

  defp valid_name?(_name), do: false

  @spec fetch_bucket(map(), String.t()) ::
          {:ok, map()} | {:error, :bucket_not_found}
  defp fetch_bucket(state, bucket) do
    case Map.fetch(state.buckets, bucket) do
      {:ok, keys} -> {:ok, keys}
      :error -> {:error, :bucket_not_found}
    end
  end

  # Runs `fun` on the bucket's key map when it exists, persists the resulting
  # key map, and updates state. `fun` returns `{reply, new_keys}`.
  @spec with_bucket(map(), String.t(), (map() -> {term(), map()})) ::
          {:reply, term(), map()}
  defp with_bucket(state, bucket, fun) do
    case fetch_bucket(state, bucket) do
      {:ok, keys} ->
        {reply, new_keys} = fun.(keys)
        persist_bucket(state.root_dir, bucket, new_keys)
        {:reply, reply, put_in(state.buckets[bucket], new_keys)}

      error ->
        {:reply, error, state}
    end
  end

  @spec prepend_version(map(), String.t(), map()) :: map()
  defp prepend_version(keys, key, version) do
    Map.update(keys, key, [version], &[version | &1])
  end

  @spec update_key(map(), String.t(), [map()]) :: map()
  defp update_key(keys, key, []), do: Map.delete(keys, key)
  defp update_key(keys, key, versions), do: Map.put(keys, key, versions)

  @spec build_version(binary(), map(), boolean()) :: map()
  defp build_version(data, metadata, is_delete_marker) do
    %{
      version_id: generate_version_id(),
      is_delete_marker: is_delete_marker,
      data: data,
      metadata: metadata,
      size: byte_size(data),
      last_modified: DateTime.utc_now()
    }
  end

  @spec generate_version_id() :: String.t()
  defp generate_version_id do
    Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  end

  @spec latest_object(map(), String.t()) ::
          {:ok, map()} | {:error, :not_found}
  defp latest_object(keys, key) do
    case Map.get(keys, key, []) do
      [%{is_delete_marker: false} = version | _rest] ->
        {:ok,
         %{
           data: version.data,
           metadata: version.metadata,
           size: version.size,
           version_id: version.version_id,
           last_modified: version.last_modified
         }}

      _other ->
        {:error, :not_found}
    end
  end

  @spec fetch_version(map(), String.t(), String.t()) ::
          {:ok, map()} | {:error, :not_found}
  defp fetch_version(keys, key, version_id) do
    versions = Map.get(keys, key, [])

    case Enum.find(versions, &(&1.version_id == version_id)) do
      nil ->
        {:error, :not_found}

      version ->
        {:ok,
         %{
           data: version.data,
           metadata: version.metadata,
           size: version.size,
           version_id: version.version_id,
           is_delete_marker: version.is_delete_marker,
           last_modified: version.last_modified
         }}
    end
  end

  @spec summarize(map()) :: version_summary()
  defp summarize(version) do
    %{
      version_id: version.version_id,
      is_delete_marker: version.is_delete_marker,
      size: version.size,
      last_modified: version.last_modified
    }
  end

  @spec current_objects(map()) :: [map()]
  defp current_objects(keys) do
    keys
    |> Enum.reduce([], fn {key, versions}, acc ->
      case versions do
        [%{is_delete_marker: false} = version | _rest] ->
          entry = %{
            key: key,
            size: version.size,
            version_id: version.version_id,
            last_modified: version.last_modified
          }

          [entry | acc]

        _other ->
          acc
      end
    end)
    |> Enum.sort_by(& &1.key)
  end

  # ── Persistence ─────────────────────────────────────────────────────────

  @spec load_buckets(String.t()) :: map()
  defp load_buckets(root) do
    case File.ls(root) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, @bucket_suffix))
        |> Enum.reduce(%{}, fn file, acc -> load_bucket_file(root, file, acc) end)

      _error ->
        %{}
    end
  end

  @spec load_bucket_file(String.t(), String.t(), map()) :: map()
  defp load_bucket_file(root, file, acc) do
    name = String.replace_suffix(file, @bucket_suffix, "")

    case File.read(Path.join(root, file)) do
      {:ok, binary} -> Map.put(acc, name, :erlang.binary_to_term(binary))
      _error -> acc
    end
  end

  @spec persist_bucket(String.t(), String.t(), map()) :: :ok
  defp persist_bucket(root, name, keys) do
    path = Path.join(root, name <> @bucket_suffix)
    File.write!(path, :erlang.term_to_binary(keys))
    :ok
  end
end
```

Reply with the `@spec` attribute alone, however many lines it needs —
not the module.
