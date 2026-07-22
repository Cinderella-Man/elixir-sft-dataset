defmodule ObjectStorage do
  @moduledoc """
  An S3-like object storage server backed by the local filesystem.

  `ObjectStorage` is a `GenServer` that manages *buckets* (flat namespaces
  identified by a name) and *objects* (binary blobs identified by a key within a
  bucket). Object data, content types and user metadata are persisted under a
  configurable `:root_dir`, so a server restarted with the same root directory
  observes the buckets and objects created by its predecessor.

  ## Layout on disk

      root_dir/
        buckets/
          <bucket-name>/
            objects/
              <hashed-key>.data   # raw object bytes
              <hashed-key>.meta   # :erlang.term_to_binary/1 of the object metadata

  Object keys may contain slashes (`"images/photo.png"`), so keys are hashed to
  build a flat, filesystem-safe file name; the original key is stored inside the
  companion `.meta` file.

  ## Multipart uploads

  Multipart uploads are held in process memory only. They are intentionally
  **ephemeral**: an upload that has not been completed is lost if the server
  restarts.

  ## Example

      {:ok, pid} = ObjectStorage.start_link(root_dir: "/tmp/store")
      :ok = ObjectStorage.create_bucket(pid, "photos")
      :ok = ObjectStorage.put_object(pid, "photos", "cat.png", <<1, 2, 3>>, "image/png")
      {:ok, %{data: <<1, 2, 3>>}} = ObjectStorage.get_object(pid, "photos", "cat.png")

  """

  use GenServer

  @default_root_dir "./object_storage_data"
  @default_content_type "application/octet-stream"
  @default_max_keys 1000
  @bucket_name_regex ~r/^[a-z0-9.\-]+$/

  @typedoc "A running `ObjectStorage` server: a pid or a registered name."
  @type server :: GenServer.server()

  @typedoc "The name of a bucket."
  @type bucket :: String.t()

  @typedoc "The key identifying an object inside a bucket."
  @type key :: String.t()

  @typedoc "Arbitrary user-supplied metadata attached to an object."
  @type metadata :: %{optional(String.t()) => String.t()}

  @typedoc "An opaque identifier for an in-progress multipart upload."
  @type upload_id :: String.t()

  @typedoc "A fully materialised object as returned by `get_object/3`."
  @type object :: %{
          data: binary(),
          content_type: String.t(),
          metadata: metadata(),
          size: non_neg_integer(),
          last_modified: DateTime.t()
        }

  @typedoc "A single entry as returned by `list_objects/3`."
  @type object_entry :: %{
          key: key(),
          size: non_neg_integer(),
          last_modified: DateTime.t()
        }

  # ----------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------

  @doc """
  Starts the object storage server.

  ## Options

    * `:root_dir` - base directory holding all persisted state. Defaults to
      `"#{@default_root_dir}"`. Reusing a directory restores its buckets and objects.
    * `:name` - optional name under which the process is registered.

  Any other option is forwarded to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {root_dir, opts} = Keyword.pop(opts, :root_dir, @default_root_dir)
    GenServer.start_link(__MODULE__, %{root_dir: root_dir}, opts)
  end

  @doc """
  Creates a bucket named `name`.

  Bucket names must be non-empty strings made of lowercase alphanumeric
  characters, hyphens and dots.

  Returns `:ok`, `{:error, :already_exists}` or `{:error, :invalid_name}`.
  """
  @spec create_bucket(server(), bucket()) :: :ok | {:error, :already_exists | :invalid_name}
  def create_bucket(server, name) do
    GenServer.call(server, {:create_bucket, name})
  end

  @doc """
  Deletes the bucket named `name`.

  The bucket must exist and must not contain any object.

  Returns `:ok`, `{:error, :not_found}` or `{:error, :not_empty}`.
  """
  @spec delete_bucket(server(), bucket()) :: :ok | {:error, :not_found | :not_empty}
  def delete_bucket(server, name) do
    GenServer.call(server, {:delete_bucket, name})
  end

  @doc """
  Returns `{:ok, names}` where `names` is the sorted list of all bucket names.
  """
  @spec list_buckets(server()) :: {:ok, [bucket()]}
  def list_buckets(server) do
    GenServer.call(server, :list_buckets)
  end

  @doc """
  Stores `data` under `key` in `bucket`.

  An existing object with the same key is silently overwritten.

  Returns `:ok` or `{:error, :bucket_not_found}`.
  """
  @spec put_object(server(), bucket(), key(), binary(), String.t(), metadata()) ::
          :ok | {:error, :bucket_not_found}
  def put_object(
        server,
        bucket,
        key,
        data,
        content_type \\ @default_content_type,
        metadata \\ %{}
      )
      when is_binary(data) do
    GenServer.call(server, {:put_object, bucket, key, data, content_type, metadata})
  end

  @doc """
  Fetches the object stored under `key` in `bucket`.

  Returns `{:ok, object}` with the object's `:data`, `:content_type`, `:metadata`,
  `:size` and `:last_modified`, or `{:error, :bucket_not_found}` / `{:error, :not_found}`.
  """
  @spec get_object(server(), bucket(), key()) ::
          {:ok, object()} | {:error, :bucket_not_found | :not_found}
  def get_object(server, bucket, key) do
    GenServer.call(server, {:get_object, bucket, key})
  end

  @doc """
  Deletes the object stored under `key` in `bucket`.

  The delete is idempotent: removing a missing key still returns `:ok`.

  Returns `:ok` or `{:error, :bucket_not_found}`.
  """
  @spec delete_object(server(), bucket(), key()) :: :ok | {:error, :bucket_not_found}
  def delete_object(server, bucket, key) do
    GenServer.call(server, {:delete_object, bucket, key})
  end

  @doc """
  Lists objects in `bucket`, sorted lexicographically by key.

  ## Options

    * `:prefix` - only keys starting with this string are returned (default `""`).
    * `:max_keys` - maximum number of entries returned (default `#{@default_max_keys}`).

  Returns `{:ok, entries}` or `{:error, :bucket_not_found}`.
  """
  @spec list_objects(server(), bucket(), keyword()) ::
          {:ok, [object_entry()]} | {:error, :bucket_not_found}
  def list_objects(server, bucket, opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "")
    max_keys = Keyword.get(opts, :max_keys, @default_max_keys)
    GenServer.call(server, {:list_objects, bucket, prefix, max_keys})
  end

  @doc """
  Copies an object, preserving its content type and metadata.

  Copying an object onto itself (same bucket and key) succeeds without doing any work.

  Returns `:ok`, `{:error, :src_bucket_not_found}`, `{:error, :dst_bucket_not_found}` or
  `{:error, :not_found}` when the source key does not exist.
  """
  @spec copy_object(server(), bucket(), key(), bucket(), key()) ::
          :ok | {:error, :src_bucket_not_found | :dst_bucket_not_found | :not_found}
  def copy_object(server, src_bucket, src_key, dst_bucket, dst_key) do
    GenServer.call(server, {:copy_object, src_bucket, src_key, dst_bucket, dst_key})
  end

  @doc """
  Initiates a multipart upload targeting `key` in `bucket`.

  The returned `upload_id` identifies the upload in `upload_part/4`,
  `complete_multipart/2` and `abort_multipart/2`.

  Returns `{:ok, upload_id}` or `{:error, :bucket_not_found}`.
  """
  @spec start_multipart(server(), bucket(), key(), String.t(), metadata()) ::
          {:ok, upload_id()} | {:error, :bucket_not_found}
  def start_multipart(
        server,
        bucket,
        key,
        content_type \\ @default_content_type,
        metadata \\ %{}
      ) do
    GenServer.call(server, {:start_multipart, bucket, key, content_type, metadata})
  end

  @doc """
  Uploads a single part of the multipart upload identified by `upload_id`.

  `part_number` is a 1-based positive integer. Parts may arrive in any order and
  re-uploading a part number replaces its previous data.

  Returns `:ok` or `{:error, :not_found}`.
  """
  @spec upload_part(server(), upload_id(), pos_integer(), binary()) ::
          :ok | {:error, :not_found}
  def upload_part(server, upload_id, part_number, data)
      when is_integer(part_number) and part_number > 0 and is_binary(data) do
    GenServer.call(server, {:upload_part, upload_id, part_number, data})
  end

  @doc """
  Completes the multipart upload identified by `upload_id`.

  Parts are concatenated in ascending `part_number` order and stored as a single
  object. The `upload_id` is invalidated afterwards.

  Returns `:ok`, `{:error, :not_found}` or `{:error, :no_parts}`.
  """
  @spec complete_multipart(server(), upload_id()) :: :ok | {:error, :not_found | :no_parts}
  def complete_multipart(server, upload_id) do
    GenServer.call(server, {:complete_multipart, upload_id})
  end

  @doc """
  Aborts the multipart upload identified by `upload_id`, discarding its parts.

  Returns `:ok` or `{:error, :not_found}`.
  """
  @spec abort_multipart(server(), upload_id()) :: :ok | {:error, :not_found}
  def abort_multipart(server, upload_id) do
    GenServer.call(server, {:abort_multipart, upload_id})
  end

  # ----------------------------------------------------------------------------
  # GenServer callbacks
  # ----------------------------------------------------------------------------

  @impl GenServer
  def init(%{root_dir: root_dir}) do
    buckets_dir = Path.join(root_dir, "buckets")
    :ok = mkdir_p!(buckets_dir)

    state = %{
      root_dir: root_dir,
      buckets_dir: buckets_dir,
      uploads: %{},
      counter: 0
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:create_bucket, name}, _from, state) do
    cond do
      not valid_bucket_name?(name) ->
        {:reply, {:error, :invalid_name}, state}

      bucket_exists?(state, name) ->
        {:reply, {:error, :already_exists}, state}

      true ->
        :ok = mkdir_p!(objects_dir(state, name))
        {:reply, :ok, state}
    end
  end

  def handle_call({:delete_bucket, name}, _from, state) do
    cond do
      not valid_bucket_name?(name) or not bucket_exists?(state, name) ->
        {:reply, {:error, :not_found}, state}

      state |> read_all_entries(name) |> Enum.any?() ->
        {:reply, {:error, :not_empty}, state}

      true ->
        _ = File.rm_rf(bucket_dir(state, name))
        {:reply, :ok, state}
    end
  end

  def handle_call(:list_buckets, _from, state) do
    names =
      case File.ls(state.buckets_dir) do
        {:ok, entries} -> entries |> Enum.filter(&valid_bucket_name?/1) |> Enum.sort()
        {:error, _reason} -> []
      end

    {:reply, {:ok, names}, state}
  end

  def handle_call({:put_object, bucket, key, data, content_type, metadata}, _from, state) do
    if bucket_exists?(state, bucket) do
      :ok = write_object(state, bucket, key, data, content_type, metadata)
      {:reply, :ok, state}
    else
      {:reply, {:error, :bucket_not_found}, state}
    end
  end

  def handle_call({:get_object, bucket, key}, _from, state) do
    {:reply, do_get_object(state, bucket, key), state}
  end

  def handle_call({:delete_object, bucket, key}, _from, state) do
    if bucket_exists?(state, bucket) do
      _ = File.rm(data_path(state, bucket, key))
      _ = File.rm(meta_path(state, bucket, key))
      {:reply, :ok, state}
    else
      {:reply, {:error, :bucket_not_found}, state}
    end
  end

  def handle_call({:list_objects, bucket, prefix, max_keys}, _from, state) do
    if bucket_exists?(state, bucket) do
      entries =
        state
        |> read_all_entries(bucket)
        |> Enum.filter(&String.starts_with?(&1.key, prefix))
        |> Enum.sort_by(& &1.key)
        |> Enum.take(max(max_keys, 0))

      {:reply, {:ok, entries}, state}
    else
      {:reply, {:error, :bucket_not_found}, state}
    end
  end

  def handle_call({:copy_object, src_bucket, src_key, dst_bucket, dst_key}, _from, state) do
    {:reply, do_copy_object(state, src_bucket, src_key, dst_bucket, dst_key), state}
  end

  def handle_call({:start_multipart, bucket, key, content_type, metadata}, _from, state) do
    if bucket_exists?(state, bucket) do
      {upload_id, state} = next_upload_id(state)

      upload = %{
        bucket: bucket,
        key: key,
        content_type: content_type,
        metadata: metadata,
        parts: %{}
      }

      {:reply, {:ok, upload_id}, put_in(state.uploads[upload_id], upload)}
    else
      {:reply, {:error, :bucket_not_found}, state}
    end
  end

  def handle_call({:upload_part, upload_id, part_number, data}, _from, state) do
    case Map.fetch(state.uploads, upload_id) do
      {:ok, upload} ->
        upload = put_in(upload.parts[part_number], data)
        {:reply, :ok, put_in(state.uploads[upload_id], upload)}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:complete_multipart, upload_id}, _from, state) do
    case Map.fetch(state.uploads, upload_id) do
      {:ok, %{parts: parts}} when map_size(parts) == 0 ->
        {:reply, {:error, :no_parts}, state}

      {:ok, upload} ->
        data =
          upload.parts
          |> Enum.sort_by(fn {part_number, _data} -> part_number end)
          |> Enum.map_join("", fn {_part_number, data} -> data end)

        state = %{state | uploads: Map.delete(state.uploads, upload_id)}

        reply =
          if bucket_exists?(state, upload.bucket) do
            write_object(
              state,
              upload.bucket,
              upload.key,
              data,
              upload.content_type,
              upload.metadata
            )
          else
            {:error, :bucket_not_found}
          end

        {:reply, reply, state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:abort_multipart, upload_id}, _from, state) do
    case Map.fetch(state.uploads, upload_id) do
      {:ok, _upload} ->
        {:reply, :ok, %{state | uploads: Map.delete(state.uploads, upload_id)}}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  # ----------------------------------------------------------------------------
  # Internal helpers
  # ----------------------------------------------------------------------------

  @spec do_get_object(map(), bucket(), key()) ::
          {:ok, object()} | {:error, :bucket_not_found | :not_found}
  defp do_get_object(state, bucket, key) do
    with true <- bucket_exists?(state, bucket) or {:error, :bucket_not_found},
         {:ok, meta} <- read_meta(state, bucket, key),
         {:ok, data} <- File.read(data_path(state, bucket, key)) do
      {:ok,
       %{
         data: data,
         content_type: meta.content_type,
         metadata: meta.metadata,
         size: byte_size(data),
         last_modified: meta.last_modified
       }}
    else
      {:error, :bucket_not_found} -> {:error, :bucket_not_found}
      _other -> {:error, :not_found}
    end
  end

  @spec do_copy_object(map(), bucket(), key(), bucket(), key()) ::
          :ok | {:error, :src_bucket_not_found | :dst_bucket_not_found | :not_found}
  defp do_copy_object(state, src_bucket, src_key, dst_bucket, dst_key) do
    cond do
      not bucket_exists?(state, src_bucket) ->
        {:error, :src_bucket_not_found}

      not bucket_exists?(state, dst_bucket) ->
        {:error, :dst_bucket_not_found}

      src_bucket == dst_bucket and src_key == dst_key ->
        case read_meta(state, src_bucket, src_key) do
          {:ok, _meta} -> :ok
          :error -> {:error, :not_found}
        end

      true ->
        case do_get_object(state, src_bucket, src_key) do
          {:ok, object} ->
            write_object(
              state,
              dst_bucket,
              dst_key,
              object.data,
              object.content_type,
              object.metadata
            )

          {:error, _reason} ->
            {:error, :not_found}
        end
    end
  end

  @spec write_object(map(), bucket(), key(), binary(), String.t(), metadata()) :: :ok
  defp write_object(state, bucket, key, data, content_type, metadata) do
    :ok = mkdir_p!(objects_dir(state, bucket))

    meta = %{
      key: key,
      content_type: content_type,
      metadata: metadata,
      size: byte_size(data),
      last_modified: DateTime.utc_now()
    }

    :ok = File.write(data_path(state, bucket, key), data)
    :ok = File.write(meta_path(state, bucket, key), :erlang.term_to_binary(meta))
    :ok
  end

  @spec read_meta(map(), bucket(), key()) :: {:ok, map()} | :error
  defp read_meta(state, bucket, key) do
    state |> meta_path(bucket, key) |> decode_meta_file()
  end

  @spec decode_meta_file(Path.t()) :: {:ok, map()} | :error
  defp decode_meta_file(path) do
    with {:ok, binary} <- File.read(path),
         %{key: _, content_type: _, metadata: _, size: _, last_modified: _} = meta <-
           safe_binary_to_term(binary) do
      {:ok, meta}
    else
      _other -> :error
    end
  end

  @spec safe_binary_to_term(binary()) :: term() | :error
  defp safe_binary_to_term(binary) do
    :erlang.binary_to_term(binary, [:safe])
  rescue
    ArgumentError -> :error
  end

  @spec read_all_entries(map(), bucket()) :: [object_entry()]
  defp read_all_entries(state, bucket) do
    dir = objects_dir(state, bucket)

    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".meta"))
        |> Enum.flat_map(fn file ->
          case dir |> Path.join(file) |> decode_meta_file() do
            {:ok, meta} ->
              [%{key: meta.key, size: meta.size, last_modified: meta.last_modified}]

            :error ->
              []
          end
        end)

      {:error, _reason} ->
        []
    end
  end

  @spec next_upload_id(map()) :: {upload_id(), map()}
  defp next_upload_id(state) do
    counter = state.counter + 1
    random = 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    {"#{random}-#{counter}", %{state | counter: counter}}
  end

  @spec valid_bucket_name?(term()) :: boolean()
  defp valid_bucket_name?(name) when is_binary(name) do
    name != "" and Regex.match?(@bucket_name_regex, name)
  end

  defp valid_bucket_name?(_name), do: false

  @spec bucket_exists?(map(), term()) :: boolean()
  defp bucket_exists?(state, name) do
    valid_bucket_name?(name) and File.dir?(bucket_dir(state, name))
  end

  @spec bucket_dir(map(), bucket()) :: Path.t()
  defp bucket_dir(state, bucket), do: Path.join(state.buckets_dir, bucket)

  @spec objects_dir(map(), bucket()) :: Path.t()
  defp objects_dir(state, bucket), do: state |> bucket_dir(bucket) |> Path.join("objects")

  @spec data_path(map(), bucket(), key()) :: Path.t()
  defp data_path(state, bucket, key) do
    state |> objects_dir(bucket) |> Path.join(hash_key(key) <> ".data")
  end

  @spec meta_path(map(), bucket(), key()) :: Path.t()
  defp meta_path(state, bucket, key) do
    state |> objects_dir(bucket) |> Path.join(hash_key(key) <> ".meta")
  end

  @spec hash_key(key()) :: String.t()
  defp hash_key(key) do
    :sha256 |> :crypto.hash(key) |> Base.encode16(case: :lower)
  end

  @spec mkdir_p!(Path.t()) :: :ok
  defp mkdir_p!(path) do
    :ok = File.mkdir_p(path)
  end
end