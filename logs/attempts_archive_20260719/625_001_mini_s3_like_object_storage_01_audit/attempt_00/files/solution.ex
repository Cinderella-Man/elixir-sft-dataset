defmodule ObjectStorage do
  @moduledoc """
  An S3-like object storage GenServer backed by the local filesystem.

  ## Filesystem Layout

      root_dir/
        buckets/
          <bucket_name>/
            objects/
              <url_encoded_key>.data      # raw object data
              <url_encoded_key>.meta       # :erlang.term_to_binary metadata
  """

  use GenServer

  # ────────────────────────────────────────────────────────────
  # Public API
  # ────────────────────────────────────────────────────────────

  @doc "Starts the ObjectStorage server linked to the current process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    root_dir = Keyword.get(opts, :root_dir, "./object_storage_data")
    name = Keyword.get(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, root_dir, server_opts)
  end

  @doc "Creates a new bucket with the given name."
  @spec create_bucket(GenServer.server(), String.t()) :: :ok | {:error, atom()}
  def create_bucket(server, name),
    do: GenServer.call(server, {:create_bucket, name})

  @doc "Deletes the bucket with the given name. Fails if it is not empty."
  @spec delete_bucket(GenServer.server(), String.t()) :: :ok | {:error, atom()}
  def delete_bucket(server, name),
    do: GenServer.call(server, {:delete_bucket, name})

  @doc "Lists all existing bucket names."
  @spec list_buckets(GenServer.server()) :: {:ok, [String.t()]}
  def list_buckets(server),
    do: GenServer.call(server, :list_buckets)

  @doc "Stores an object in the given bucket under the given key."
  @spec put_object(
          GenServer.server(),
          String.t(),
          String.t(),
          binary(),
          String.t(),
          map()
        ) :: :ok | {:error, atom()}
  def put_object(
        server,
        bucket,
        key,
        data,
        content_type \\ "application/octet-stream",
        metadata \\ %{}
      ) do
    GenServer.call(server, {:put_object, bucket, key, data, content_type, metadata})
  end

  @doc "Retrieves an object from the given bucket."
  @spec get_object(GenServer.server(), String.t(), String.t()) ::
          {:ok, map()} | {:error, atom()}
  def get_object(server, bucket, key),
    do: GenServer.call(server, {:get_object, bucket, key})

  @doc "Deletes an object from the given bucket."
  @spec delete_object(GenServer.server(), String.t(), String.t()) ::
          :ok | {:error, atom()}
  def delete_object(server, bucket, key),
    do: GenServer.call(server, {:delete_object, bucket, key})

  @doc "Lists objects in a bucket, optionally filtered by `:prefix` and `:max_keys`."
  @spec list_objects(GenServer.server(), String.t(), keyword()) ::
          {:ok, [map()]} | {:error, atom()}
  def list_objects(server, bucket, opts \\ []),
    do: GenServer.call(server, {:list_objects, bucket, opts})

  @doc "Copies an object from one bucket/key to another."
  @spec copy_object(
          GenServer.server(),
          String.t(),
          String.t(),
          String.t(),
          String.t()
        ) :: :ok | {:error, atom()}
  def copy_object(server, src_bucket, src_key, dst_bucket, dst_key),
    do: GenServer.call(server, {:copy_object, src_bucket, src_key, dst_bucket, dst_key})

  @doc "Initiates a multipart upload, returning an upload ID."
  @spec start_multipart(
          GenServer.server(),
          String.t(),
          String.t(),
          String.t(),
          map()
        ) :: {:ok, String.t()} | {:error, atom()}
  def start_multipart(
        server,
        bucket,
        key,
        content_type \\ "application/octet-stream",
        metadata \\ %{}
      ) do
    GenServer.call(server, {:start_multipart, bucket, key, content_type, metadata})
  end

  @doc "Uploads a numbered part for the given multipart upload ID."
  @spec upload_part(GenServer.server(), String.t(), pos_integer(), binary()) ::
          :ok | {:error, atom()}
  def upload_part(server, upload_id, part_number, data),
    do: GenServer.call(server, {:upload_part, upload_id, part_number, data})

  @doc "Completes a multipart upload, assembling all parts into the final object."
  @spec complete_multipart(GenServer.server(), String.t()) :: :ok | {:error, atom()}
  def complete_multipart(server, upload_id),
    do: GenServer.call(server, {:complete_multipart, upload_id})

  @doc "Aborts a multipart upload and discards all uploaded parts."
  @spec abort_multipart(GenServer.server(), String.t()) :: :ok | {:error, atom()}
  def abort_multipart(server, upload_id),
    do: GenServer.call(server, {:abort_multipart, upload_id})

  # ────────────────────────────────────────────────────────────
  # GenServer callbacks
  # ────────────────────────────────────────────────────────────

  @impl true
  def init(root_dir) do
    root_dir = Path.expand(root_dir)
    buckets_dir = Path.join(root_dir, "buckets")
    File.mkdir_p!(buckets_dir)

    state = %{
      root_dir: root_dir,
      buckets_dir: buckets_dir,
      # multipart uploads are ephemeral (in-memory only)
      # %{upload_id => %{bucket, key, content_type, metadata, parts}}
      multipart_uploads: %{}
    }

    {:ok, state}
  end

  # ── create_bucket ──────────────────────────────────────────

  @impl true
  def handle_call({:create_bucket, name}, _from, state) do
    with :ok <- validate_bucket_name(name) do
      bucket_path = bucket_dir(state, name)

      if File.dir?(bucket_path) do
        {:reply, {:error, :already_exists}, state}
      else
        File.mkdir_p!(objects_dir(state, name))
        {:reply, :ok, state}
      end
    else
      {:error, _} = err -> {:reply, err, state}
    end
  end

  # ── delete_bucket ──────────────────────────────────────────

  def handle_call({:delete_bucket, name}, _from, state) do
    bucket_path = bucket_dir(state, name)

    cond do
      not File.dir?(bucket_path) ->
        {:reply, {:error, :not_found}, state}

      not bucket_empty?(state, name) ->
        {:reply, {:error, :not_empty}, state}

      true ->
        File.rm_rf!(bucket_path)
        {:reply, :ok, state}
    end
  end

  # ── list_buckets ───────────────────────────────────────────

  def handle_call(:list_buckets, _from, state) do
    buckets =
      state.buckets_dir
      |> File.ls!()
      |> Enum.filter(&File.dir?(Path.join(state.buckets_dir, &1)))
      |> Enum.sort()

    {:reply, {:ok, buckets}, state}
  end

  # ── put_object ─────────────────────────────────────────────

  def handle_call({:put_object, bucket, key, data, content_type, metadata}, _from, state) do
    if not bucket_exists?(state, bucket) do
      {:reply, {:error, :bucket_not_found}, state}
    else
      write_object(state, bucket, key, data, content_type, metadata)
      {:reply, :ok, state}
    end
  end

  # ── get_object ─────────────────────────────────────────────

  def handle_call({:get_object, bucket, key}, _from, state) do
    cond do
      not bucket_exists?(state, bucket) ->
        {:reply, {:error, :bucket_not_found}, state}

      not object_exists?(state, bucket, key) ->
        {:reply, {:error, :not_found}, state}

      true ->
        {:reply, {:ok, read_object(state, bucket, key)}, state}
    end
  end

  # ── delete_object ──────────────────────────────────────────

  def handle_call({:delete_object, bucket, key}, _from, state) do
    if not bucket_exists?(state, bucket) do
      {:reply, {:error, :bucket_not_found}, state}
    else
      data_path = object_data_path(state, bucket, key)
      meta_path = object_meta_path(state, bucket, key)
      File.rm(data_path)
      File.rm(meta_path)
      {:reply, :ok, state}
    end
  end

  # ── list_objects ───────────────────────────────────────────

  def handle_call({:list_objects, bucket, opts}, _from, state) do
    if not bucket_exists?(state, bucket) do
      {:reply, {:error, :bucket_not_found}, state}
    else
      prefix = Keyword.get(opts, :prefix, "")
      max_keys = Keyword.get(opts, :max_keys, 1000)

      objects =
        state
        |> all_object_keys(bucket)
        |> Enum.filter(&String.starts_with?(&1, prefix))
        |> Enum.sort()
        |> Enum.take(max_keys)
        |> Enum.map(&object_summary(state, bucket, &1))

      {:reply, {:ok, objects}, state}
    end
  end

  # ── copy_object ────────────────────────────────────────────

  def handle_call({:copy_object, src_bucket, src_key, dst_bucket, dst_key}, _from, state) do
    cond do
      not bucket_exists?(state, src_bucket) ->
        {:reply, {:error, :src_bucket_not_found}, state}

      not bucket_exists?(state, dst_bucket) ->
        {:reply, {:error, :dst_bucket_not_found}, state}

      not object_exists?(state, src_bucket, src_key) ->
        {:reply, {:error, :not_found}, state}

      src_bucket == dst_bucket and src_key == dst_key ->
        {:reply, :ok, state}

      true ->
        obj = read_object(state, src_bucket, src_key)
        write_object(state, dst_bucket, dst_key, obj.data, obj.content_type, obj.metadata)
        {:reply, :ok, state}
    end
  end

  # ── start_multipart ────────────────────────────────────────

  def handle_call({:start_multipart, bucket, key, content_type, metadata}, _from, state) do
    if not bucket_exists?(state, bucket) do
      {:reply, {:error, :bucket_not_found}, state}
    else
      upload_id = generate_upload_id()

      upload = %{
        bucket: bucket,
        key: key,
        content_type: content_type,
        metadata: metadata,
        parts: %{}
      }

      state = put_in(state, [:multipart_uploads, upload_id], upload)
      {:reply, {:ok, upload_id}, state}
    end
  end

  # ── upload_part ────────────────────────────────────────────

  def handle_call({:upload_part, upload_id, part_number, data}, _from, state) do
    case Map.fetch(state.multipart_uploads, upload_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, _upload} ->
        state = put_in(state, [:multipart_uploads, upload_id, :parts, part_number], data)
        {:reply, :ok, state}
    end
  end

  # ── complete_multipart ─────────────────────────────────────

  def handle_call({:complete_multipart, upload_id}, _from, state) do
    case Map.fetch(state.multipart_uploads, upload_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, %{parts: parts}} when map_size(parts) == 0 ->
        {:reply, {:error, :no_parts}, state}

      {:ok, upload} ->
        assembled =
          upload.parts
          |> Enum.sort_by(fn {part_num, _data} -> part_num end)
          |> Enum.map(fn {_part_num, data} -> data end)
          |> IO.iodata_to_binary()

        write_object(
          state,
          upload.bucket,
          upload.key,
          assembled,
          upload.content_type,
          upload.metadata
        )

        state = %{state | multipart_uploads: Map.delete(state.multipart_uploads, upload_id)}
        {:reply, :ok, state}
    end
  end

  # ── abort_multipart ────────────────────────────────────────

  def handle_call({:abort_multipart, upload_id}, _from, state) do
    if Map.has_key?(state.multipart_uploads, upload_id) do
      state = %{state | multipart_uploads: Map.delete(state.multipart_uploads, upload_id)}
      {:reply, :ok, state}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  # ────────────────────────────────────────────────────────────
  # Internal helpers
  # ────────────────────────────────────────────────────────────

  @bucket_name_re ~r/\A[a-z0-9.\-]+\z/

  defp validate_bucket_name(name) when is_binary(name) and byte_size(name) > 0 do
    if Regex.match?(@bucket_name_re, name), do: :ok, else: {:error, :invalid_name}
  end

  defp validate_bucket_name(_), do: {:error, :invalid_name}

  # ── path helpers ───────────────────────────────────────────

  defp bucket_dir(state, bucket), do: Path.join(state.buckets_dir, bucket)
  defp objects_dir(state, bucket), do: Path.join(bucket_dir(state, bucket), "objects")

  defp encode_key(key) do
    key
    |> :erlang.term_to_binary()
    |> Base.url_encode64(padding: false)
  end

  defp object_data_path(state, bucket, key) do
    Path.join(objects_dir(state, bucket), encode_key(key) <> ".data")
  end

  defp object_meta_path(state, bucket, key) do
    Path.join(objects_dir(state, bucket), encode_key(key) <> ".meta")
  end

  # ── bucket / object existence ──────────────────────────────

  defp bucket_exists?(state, bucket), do: File.dir?(bucket_dir(state, bucket))

  defp object_exists?(state, bucket, key),
    do: File.regular?(object_data_path(state, bucket, key))

  defp bucket_empty?(state, bucket) do
    obj_dir = objects_dir(state, bucket)

    case File.ls(obj_dir) do
      {:ok, []} -> true
      {:ok, _files} -> false
      {:error, :enoent} -> true
    end
  end

  # ── read / write objects ───────────────────────────────────

  defp write_object(state, bucket, key, data, content_type, metadata) do
    data_path = object_data_path(state, bucket, key)
    meta_path = object_meta_path(state, bucket, key)

    File.mkdir_p!(Path.dirname(data_path))

    meta = %{
      content_type: content_type,
      metadata: metadata,
      size: byte_size(data),
      last_modified: DateTime.utc_now()
    }

    File.write!(data_path, data)
    File.write!(meta_path, :erlang.term_to_binary(meta))
  end

  defp read_object(state, bucket, key) do
    data_path = object_data_path(state, bucket, key)
    meta_path = object_meta_path(state, bucket, key)

    data = File.read!(data_path)
    meta = meta_path |> File.read!() |> :erlang.binary_to_term()

    %{
      data: data,
      content_type: meta.content_type,
      metadata: meta.metadata,
      size: meta.size,
      last_modified: meta.last_modified
    }
  end

  # ── listing helpers ────────────────────────────────────────

  defp all_object_keys(state, bucket) do
    obj_dir = objects_dir(state, bucket)

    case File.ls(obj_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".meta"))
        |> Enum.map(fn filename ->
          filename
          |> String.trim_trailing(".meta")
          |> Base.url_decode64!(padding: false)
          |> :erlang.binary_to_term()
        end)

      {:error, :enoent} ->
        []
    end
  end

  defp object_summary(state, bucket, key) do
    meta_path = object_meta_path(state, bucket, key)
    meta = meta_path |> File.read!() |> :erlang.binary_to_term()

    %{
      key: key,
      size: meta.size,
      last_modified: meta.last_modified
    }
  end

  # ── multipart helpers ──────────────────────────────────────

  defp generate_upload_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
