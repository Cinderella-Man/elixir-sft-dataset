defmodule VersionedObjectStorage do
  @moduledoc """
  An S3-like, versioned object store backed by the local filesystem.

  Every `put_object/5` call appends a brand-new *version* of the key; earlier versions are
  never destroyed. `delete_object/3` performs a soft delete by appending a *delete marker*
  version, which hides the key from `get_object/3` and `list_objects/2` while preserving the
  full history. `delete_version/4` permanently removes a single version — removing the latest
  delete marker therefore restores the object.

  ## Storage layout

  All state lives under `:root_dir`:

      <root_dir>/buckets/<bucket>/objects/<url_safe_key>/<version_id>.bin

  Each `.bin` file holds `:erlang.term_to_binary/1` of a complete version record (data,
  metadata, size, sequence number and timestamp). The bucket directory itself records the
  bucket's existence, so buckets, versions and delete markers all survive a restart as long
  as the same `:root_dir` is reused. On `init/1` the whole tree is scanned to rebuild an
  in-memory index (object payloads stay on disk and are read on demand).

  Recency is tracked by a monotonically increasing sequence number stored inside every
  version record; the highest sequence number for a key is its latest version.
  """

  use GenServer

  @default_root "./versioned_object_storage_data"
  @bucket_name_regex ~r/^[a-z0-9.\-]+$/

  @typedoc "A bucket name."
  @type bucket :: String.t()

  @typedoc "An object key."
  @type key :: String.t()

  @typedoc "A unique version identifier."
  @type version_id :: String.t()

  @typedoc "Summary of a single stored version."
  @type version_info :: %{
          version_id: version_id(),
          is_delete_marker: boolean(),
          size: non_neg_integer(),
          last_modified: DateTime.t()
        }

  @typedoc "Summary of a key's current (latest, non-deleted) state."
  @type object_info :: %{
          key: key(),
          size: non_neg_integer(),
          version_id: version_id(),
          last_modified: DateTime.t()
        }

  # ----------------------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------------------

  @doc """
  Starts the storage server.

  Options:

    * `:root_dir` — base directory for all persisted state (default
      `"#{@default_root}"`).
    * `:name` — optional name for process registration.

  Any other option is ignored.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Creates a bucket.

  Returns `:ok`, `{:error, :already_exists}` when the bucket exists, or
  `{:error, :invalid_name}` when `name` is not a non-empty string of lowercase alphanumeric
  characters, hyphens and dots.
  """
  @spec create_bucket(GenServer.server(), bucket()) ::
          :ok | {:error, :already_exists | :invalid_name}
  def create_bucket(server, name) do
    GenServer.call(server, {:create_bucket, name})
  end

  @doc """
  Returns `{:ok, buckets}` where `buckets` is the sorted list of existing bucket names.
  """
  @spec list_buckets(GenServer.server()) :: {:ok, [bucket()]}
  def list_buckets(server) do
    GenServer.call(server, :list_buckets)
  end

  @doc """
  Stores a new version of `key` in `bucket`.

  `data` is a binary payload and `metadata` an arbitrary map. Existing versions are kept.
  Returns `{:ok, version_id}` or `{:error, :bucket_not_found}`.
  """
  @spec put_object(GenServer.server(), bucket(), key(), binary(), map()) ::
          {:ok, version_id()} | {:error, :bucket_not_found}
  def put_object(server, bucket, key, data, metadata \\ %{})
      when is_binary(data) and is_map(metadata) do
    GenServer.call(server, {:put_object, bucket, key, data, metadata})
  end

  @doc """
  Retrieves the latest version of `key`.

  Returns `{:ok, %{data: binary, metadata: map, size: integer, version_id: string,
  last_modified: DateTime.t()}}`, `{:error, :bucket_not_found}`, or `{:error, :not_found}`
  when the key has no versions or its latest version is a delete marker.
  """
  @spec get_object(GenServer.server(), bucket(), key()) ::
          {:ok, map()} | {:error, :bucket_not_found | :not_found}
  def get_object(server, bucket, key) do
    GenServer.call(server, {:get_object, bucket, key})
  end

  @doc """
  Retrieves one specific version of `key` by `version_id`.

  Returns `{:ok, %{data: binary, metadata: map, size: integer, version_id: string,
  is_delete_marker: boolean, last_modified: DateTime.t()}}`. Delete markers carry `""` as
  their data. Returns `{:error, :bucket_not_found}` or `{:error, :not_found}`.
  """
  @spec get_object_version(GenServer.server(), bucket(), key(), version_id()) ::
          {:ok, map()} | {:error, :bucket_not_found | :not_found}
  def get_object_version(server, bucket, key, version_id) do
    GenServer.call(server, {:get_object_version, bucket, key, version_id})
  end

  @doc """
  Soft-deletes `key` by appending a delete marker version.

  Earlier versions are preserved and remain reachable through `list_versions/3` and
  `get_object_version/4`. Returns `{:ok, version_id}` of the delete marker, or
  `{:error, :bucket_not_found}`.
  """
  @spec delete_object(GenServer.server(), bucket(), key()) ::
          {:ok, version_id()} | {:error, :bucket_not_found}
  def delete_object(server, bucket, key) do
    GenServer.call(server, {:delete_object, bucket, key})
  end

  @doc """
  Lists every version of `key`, newest first.

  Returns `{:ok, [%{version_id: string, is_delete_marker: boolean, size: integer,
  last_modified: DateTime.t()}]}` (`{:ok, []}` when the key has no versions), or
  `{:error, :bucket_not_found}`.
  """
  @spec list_versions(GenServer.server(), bucket(), key()) ::
          {:ok, [version_info()]} | {:error, :bucket_not_found}
  def list_versions(server, bucket, key) do
    GenServer.call(server, {:list_versions, bucket, key})
  end

  @doc """
  Permanently removes a single version of `key`.

  Idempotent: returns `:ok` even when the version does not exist. Removing the latest delete
  marker restores the object, as the remaining highest-recency version becomes the latest.
  Returns `{:error, :bucket_not_found}` when the bucket is missing.
  """
  @spec delete_version(GenServer.server(), bucket(), key(), version_id()) ::
          :ok | {:error, :bucket_not_found}
  def delete_version(server, bucket, key, version_id) do
    GenServer.call(server, {:delete_version, bucket, key, version_id})
  end

  @doc """
  Lists the current contents of `bucket`.

  Only keys whose latest version is a real object (not a delete marker) are returned, sorted
  lexicographically by key. Returns `{:error, :bucket_not_found}` when the bucket is missing.
  """
  @spec list_objects(GenServer.server(), bucket()) ::
          {:ok, [object_info()]} | {:error, :bucket_not_found}
  def list_objects(server, bucket) do
    GenServer.call(server, {:list_objects, bucket})
  end

  # ----------------------------------------------------------------------------------------
  # GenServer callbacks
  # ----------------------------------------------------------------------------------------

  @impl true
  def init(opts) do
    root_dir = Keyword.get(opts, :root_dir, @default_root)
    buckets_dir = Path.join(root_dir, "buckets")
    File.mkdir_p!(buckets_dir)

    {buckets, max_seq} = load_buckets(buckets_dir)

    {:ok,
     %{
       root_dir: root_dir,
       buckets_dir: buckets_dir,
       buckets: buckets,
       seq: max_seq + 1
     }}
  end

  @impl true
  def handle_call({:create_bucket, name}, _from, state) do
    cond do
      not valid_bucket_name?(name) ->
        {:reply, {:error, :invalid_name}, state}

      Map.has_key?(state.buckets, name) ->
        {:reply, {:error, :already_exists}, state}

      true ->
        File.mkdir_p!(Path.join([state.buckets_dir, name, "objects"]))
        {:reply, :ok, put_in(state.buckets[name], %{})}
    end
  end

  def handle_call(:list_buckets, _from, state) do
    {:reply, {:ok, state.buckets |> Map.keys() |> Enum.sort()}, state}
  end

  def handle_call({:put_object, bucket, key, data, metadata}, _from, state) do
    with_bucket(state, bucket, fn keys ->
      {entry, state} = new_entry(state, key, byte_size(data), metadata, false)
      :ok = write_version(state, bucket, key, entry, data)
      versions = [entry | Map.get(keys, key, [])]
      {{:ok, entry.version_id}, put_in(state.buckets[bucket], Map.put(keys, key, versions))}
    end)
  end

  def handle_call({:delete_object, bucket, key}, _from, state) do
    with_bucket(state, bucket, fn keys ->
      {entry, state} = new_entry(state, key, 0, %{}, true)
      :ok = write_version(state, bucket, key, entry, "")
      versions = [entry | Map.get(keys, key, [])]
      {{:ok, entry.version_id}, put_in(state.buckets[bucket], Map.put(keys, key, versions))}
    end)
  end

  def handle_call({:get_object, bucket, key}, _from, state) do
    with_bucket(state, bucket, fn keys ->
      case latest(keys, key) do
        nil ->
          {{:error, :not_found}, state}

        %{is_delete_marker: true} ->
          {{:error, :not_found}, state}

        entry ->
          record = read_version!(state, bucket, key, entry.version_id)

          reply = %{
            data: record.data,
            metadata: record.metadata,
            size: record.size,
            version_id: record.version_id,
            last_modified: record.last_modified
          }

          {{:ok, reply}, state}
      end
    end)
  end

  def handle_call({:get_object_version, bucket, key, version_id}, _from, state) do
    with_bucket(state, bucket, fn keys ->
      versions = Map.get(keys, key, [])

      case Enum.find(versions, &(&1.version_id == version_id)) do
        nil ->
          {{:error, :not_found}, state}

        _entry ->
          record = read_version!(state, bucket, key, version_id)

          reply = %{
            data: record.data,
            metadata: record.metadata,
            size: record.size,
            version_id: record.version_id,
            is_delete_marker: record.is_delete_marker,
            last_modified: record.last_modified
          }

          {{:ok, reply}, state}
      end
    end)
  end

  def handle_call({:list_versions, bucket, key}, _from, state) do
    with_bucket(state, bucket, fn keys ->
      infos =
        keys
        |> Map.get(key, [])
        |> Enum.map(fn entry ->
          %{
            version_id: entry.version_id,
            is_delete_marker: entry.is_delete_marker,
            size: entry.size,
            last_modified: entry.last_modified
          }
        end)

      {{:ok, infos}, state}
    end)
  end

  def handle_call({:delete_version, bucket, key, version_id}, _from, state) do
    with_bucket(state, bucket, fn keys ->
      _ = File.rm(version_path(state, bucket, key, version_id))

      versions =
        keys
        |> Map.get(key, [])
        |> Enum.reject(&(&1.version_id == version_id))

      {:ok, put_in(state.buckets[bucket], Map.put(keys, key, versions))}
    end)
  end

  def handle_call({:list_objects, bucket}, _from, state) do
    with_bucket(state, bucket, fn keys ->
      objects =
        keys
        |> Enum.flat_map(fn {key, versions} ->
          case versions do
            [%{is_delete_marker: false} = entry | _] ->
              [
                %{
                  key: key,
                  size: entry.size,
                  version_id: entry.version_id,
                  last_modified: entry.last_modified
                }
              ]

            _ ->
              []
          end
        end)
        |> Enum.sort_by(& &1.key)

      {{:ok, objects}, state}
    end)
  end

  # ----------------------------------------------------------------------------------------
  # Internal helpers
  # ----------------------------------------------------------------------------------------

  @spec with_bucket(map(), bucket(), (map() -> {term(), map()})) ::
          {:reply, term(), map()}
  defp with_bucket(state, bucket, fun) do
    case Map.fetch(state.buckets, bucket) do
      {:ok, keys} ->
        {reply, new_state} = fun.(keys)
        {:reply, reply, new_state}

      :error ->
        {:reply, {:error, :bucket_not_found}, state}
    end
  end

  @spec latest(map(), key()) :: map() | nil
  defp latest(keys, key) do
    case Map.get(keys, key, []) do
      [entry | _] -> entry
      [] -> nil
    end
  end

  @spec new_entry(map(), key(), non_neg_integer(), map(), boolean()) :: {map(), map()}
  defp new_entry(state, key, size, metadata, delete_marker?) do
    entry = %{
      version_id: generate_version_id(),
      seq: state.seq,
      key: key,
      size: size,
      metadata: metadata,
      is_delete_marker: delete_marker?,
      last_modified: DateTime.utc_now()
    }

    {entry, %{state | seq: state.seq + 1}}
  end

  @spec generate_version_id() :: version_id()
  defp generate_version_id do
    Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
  end

  @spec valid_bucket_name?(term()) :: boolean()
  defp valid_bucket_name?(name) when is_binary(name) and byte_size(name) > 0 do
    Regex.match?(@bucket_name_regex, name)
  end

  defp valid_bucket_name?(_name), do: false

  @spec write_version(map(), bucket(), key(), map(), binary()) :: :ok
  defp write_version(state, bucket, key, entry, data) do
    dir = key_dir(state, bucket, key)
    File.mkdir_p!(dir)

    path = Path.join(dir, entry.version_id <> ".bin")
    tmp_path = path <> ".tmp"

    File.write!(tmp_path, :erlang.term_to_binary(Map.put(entry, :data, data)))
    File.rename!(tmp_path, path)
    :ok
  end

  @spec read_version!(map(), bucket(), key(), version_id()) :: map()
  defp read_version!(state, bucket, key, version_id) do
    state
    |> version_path(bucket, key, version_id)
    |> File.read!()
    |> :erlang.binary_to_term()
  end

  @spec key_dir(map(), bucket(), key()) :: Path.t()
  defp key_dir(state, bucket, key) do
    Path.join([state.buckets_dir, bucket, "objects", encode_key(key)])
  end

  @spec version_path(map(), bucket(), key(), version_id()) :: Path.t()
  defp version_path(state, bucket, key, version_id) do
    Path.join(key_dir(state, bucket, key), version_id <> ".bin")
  end

  @spec encode_key(key()) :: String.t()
  defp encode_key(key), do: Base.url_encode64(key, padding: false)

  # -- restart recovery --------------------------------------------------------------------

  @spec load_buckets(Path.t()) :: {map(), non_neg_integer()}
  defp load_buckets(buckets_dir) do
    buckets_dir
    |> list_dir()
    |> Enum.filter(&File.dir?(Path.join(buckets_dir, &1)))
    |> Enum.reduce({%{}, 0}, fn bucket, {acc, max_seq} ->
      {keys, bucket_max} = load_bucket(Path.join([buckets_dir, bucket, "objects"]))
      {Map.put(acc, bucket, keys), max(max_seq, bucket_max)}
    end)
  end

  @spec load_bucket(Path.t()) :: {map(), non_neg_integer()}
  defp load_bucket(objects_dir) do
    objects_dir
    |> list_dir()
    |> Enum.filter(&File.dir?(Path.join(objects_dir, &1)))
    |> Enum.reduce({%{}, 0}, fn enc_key, {acc, max_seq} ->
      entries = load_key(Path.join(objects_dir, enc_key))

      case entries do
        [] ->
          {acc, max_seq}

        [%{key: key} | _] ->
          key_max = entries |> Enum.map(& &1.seq) |> Enum.max()
          {Map.put(acc, key, entries), max(max_seq, key_max)}
      end
    end)
  end

  @spec load_key(Path.t()) :: [map()]
  defp load_key(key_path) do
    key_path
    |> list_dir()
    |> Enum.filter(&String.ends_with?(&1, ".bin"))
    |> Enum.flat_map(fn file ->
      case File.read(Path.join(key_path, file)) do
        {:ok, binary} -> [binary |> :erlang.binary_to_term() |> Map.delete(:data)]
        {:error, _reason} -> []
      end
    end)
    |> Enum.sort_by(& &1.seq, :desc)
  end

  @spec list_dir(Path.t()) :: [String.t()]
  defp list_dir(path) do
    case File.ls(path) do
      {:ok, entries} -> entries
      {:error, _reason} -> []
    end
  end
end