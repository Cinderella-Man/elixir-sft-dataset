# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
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
```

## Test harness — implement the `# TODO` test

```elixir
defmodule ObjectStorageTest do
  use ExUnit.Case, async: false

  # ExUnit's :tmp_dir tag derives a deterministic path from module + test name, so
  # concurrent runs of this harness (separate OS processes sharing a CWD) collide on
  # the same directories. Build a per-run unique root instead: System.pid/0 separates
  # BEAM instances and the random suffix guards against OS pid reuse. Cleanup uses
  # the non-raising rm_rf/1 — the path is never reused, so leftovers are harmless.
  setup do
    unique =
      "#{System.pid()}-#{System.unique_integer([:positive])}-" <>
        Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)

    tmp_dir = Path.expand(Path.join(["tmp", "object_storage_test", unique]))
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf(tmp_dir) end)

    {:ok, pid} = ObjectStorage.start_link(root_dir: tmp_dir)
    %{os: pid, tmp_dir: tmp_dir}
  end

  # -------------------------------------------------------
  # Bucket CRUD
  # -------------------------------------------------------

  test "create and list buckets", %{os: os} do
    assert :ok = ObjectStorage.create_bucket(os, "alpha")
    assert :ok = ObjectStorage.create_bucket(os, "beta")
    assert {:ok, ["alpha", "beta"]} = ObjectStorage.list_buckets(os)
  end

  test "creating a duplicate bucket returns error", %{os: os} do
    assert :ok = ObjectStorage.create_bucket(os, "photos")
    assert {:error, :already_exists} = ObjectStorage.create_bucket(os, "photos")
  end

  test "invalid bucket names are rejected", %{os: os} do
    assert {:error, :invalid_name} = ObjectStorage.create_bucket(os, "")
    assert {:error, :invalid_name} = ObjectStorage.create_bucket(os, "UPPER")
    assert {:error, :invalid_name} = ObjectStorage.create_bucket(os, "has space")
    assert {:error, :invalid_name} = ObjectStorage.create_bucket(os, "under_score")
  end

  test "valid bucket names with hyphens and dots", %{os: os} do
    assert :ok = ObjectStorage.create_bucket(os, "my-bucket")
    assert :ok = ObjectStorage.create_bucket(os, "my.bucket.v2")
    assert :ok = ObjectStorage.create_bucket(os, "abc123")
  end

  test "delete an empty bucket", %{os: os} do
    ObjectStorage.create_bucket(os, "temp")
    assert :ok = ObjectStorage.delete_bucket(os, "temp")
    assert {:ok, []} = ObjectStorage.list_buckets(os)
  end

  test "delete a non-existent bucket returns error", %{os: os} do
    assert {:error, :not_found} = ObjectStorage.delete_bucket(os, "ghost")
  end

  test "delete a non-empty bucket returns error", %{os: os} do
    ObjectStorage.create_bucket(os, "full")
    ObjectStorage.put_object(os, "full", "file.txt", "hello")
    assert {:error, :not_empty} = ObjectStorage.delete_bucket(os, "full")
  end

  # -------------------------------------------------------
  # Object CRUD
  # -------------------------------------------------------

  test "put and get an object", %{os: os} do
    ObjectStorage.create_bucket(os, "data")

    assert :ok =
             ObjectStorage.put_object(os, "data", "greeting.txt", "hello world", "text/plain", %{
               "author" => "test"
             })

    assert {:ok, obj} = ObjectStorage.get_object(os, "data", "greeting.txt")
    assert obj.data == "hello world"
    assert obj.content_type == "text/plain"
    assert obj.metadata == %{"author" => "test"}
    assert obj.size == byte_size("hello world")
    assert %DateTime{} = obj.last_modified
  end

  test "put overwrites an existing object silently", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    ObjectStorage.put_object(os, "b", "k", "v1")
    ObjectStorage.put_object(os, "b", "k", "v2")

    assert {:ok, %{data: "v2"}} = ObjectStorage.get_object(os, "b", "k")
  end

  test "get from non-existent bucket", %{os: os} do
    # TODO
  end

  test "get a non-existent key", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    assert {:error, :not_found} = ObjectStorage.get_object(os, "b", "missing")
  end

  test "put to non-existent bucket", %{os: os} do
    assert {:error, :bucket_not_found} = ObjectStorage.put_object(os, "nope", "k", "v")
  end

  test "default content_type is application/octet-stream", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    ObjectStorage.put_object(os, "b", "k", "data")

    assert {:ok, %{content_type: "application/octet-stream"}} =
             ObjectStorage.get_object(os, "b", "k")
  end

  test "delete an object", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    ObjectStorage.put_object(os, "b", "k", "v")
    assert :ok = ObjectStorage.delete_object(os, "b", "k")
    assert {:error, :not_found} = ObjectStorage.get_object(os, "b", "k")
  end

  test "delete is idempotent — deleting a missing key succeeds", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    assert :ok = ObjectStorage.delete_object(os, "b", "never-existed")
  end

  test "delete from non-existent bucket returns error", %{os: os} do
    assert {:error, :bucket_not_found} = ObjectStorage.delete_object(os, "nope", "k")
  end

  # -------------------------------------------------------
  # Binary data
  # -------------------------------------------------------

  test "stores and retrieves raw binary data correctly", %{os: os} do
    ObjectStorage.create_bucket(os, "bin")
    blob = :crypto.strong_rand_bytes(4096)
    ObjectStorage.put_object(os, "bin", "random.bin", blob, "application/octet-stream")

    assert {:ok, %{data: ^blob, size: 4096}} = ObjectStorage.get_object(os, "bin", "random.bin")
  end

  # -------------------------------------------------------
  # Listing with prefix and max_keys
  # -------------------------------------------------------

  test "list_objects returns all keys sorted", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    ObjectStorage.put_object(os, "b", "c.txt", "")
    ObjectStorage.put_object(os, "b", "a.txt", "")
    ObjectStorage.put_object(os, "b", "b.txt", "")

    assert {:ok, objects} = ObjectStorage.list_objects(os, "b")
    keys = Enum.map(objects, & &1.key)
    assert keys == ["a.txt", "b.txt", "c.txt"]
  end

  test "list_objects with prefix filter", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    ObjectStorage.put_object(os, "b", "images/cat.png", "")
    ObjectStorage.put_object(os, "b", "images/dog.png", "")
    ObjectStorage.put_object(os, "b", "docs/readme.md", "")

    assert {:ok, objects} = ObjectStorage.list_objects(os, "b", prefix: "images/")
    keys = Enum.map(objects, & &1.key)
    assert keys == ["images/cat.png", "images/dog.png"]
  end

  test "list_objects with max_keys", %{os: os} do
    ObjectStorage.create_bucket(os, "b")

    for i <- 1..10,
        do: ObjectStorage.put_object(os, "b", "file-#{String.pad_leading("#{i}", 2, "0")}", "")

    assert {:ok, objects} = ObjectStorage.list_objects(os, "b", max_keys: 3)
    assert length(objects) == 3
  end

  test "list_objects includes size and last_modified", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    ObjectStorage.put_object(os, "b", "k", "12345")

    assert {:ok, [obj]} = ObjectStorage.list_objects(os, "b")
    assert obj.key == "k"
    assert obj.size == 5
    assert %DateTime{} = obj.last_modified
  end

  test "list_objects on non-existent bucket", %{os: os} do
    assert {:error, :bucket_not_found} = ObjectStorage.list_objects(os, "nope")
  end

  test "list_objects on empty bucket returns empty list", %{os: os} do
    ObjectStorage.create_bucket(os, "empty")
    assert {:ok, []} = ObjectStorage.list_objects(os, "empty")
  end

  # -------------------------------------------------------
  # Copy
  # -------------------------------------------------------

  test "copy an object within the same bucket", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    ObjectStorage.put_object(os, "b", "src", "payload", "text/plain", %{"tag" => "1"})

    assert :ok = ObjectStorage.copy_object(os, "b", "src", "b", "dst")

    assert {:ok, obj} = ObjectStorage.get_object(os, "b", "dst")
    assert obj.data == "payload"
    assert obj.content_type == "text/plain"
    assert obj.metadata == %{"tag" => "1"}

    # Source still exists
    assert {:ok, _} = ObjectStorage.get_object(os, "b", "src")
  end

  test "copy an object across buckets", %{os: os} do
    ObjectStorage.create_bucket(os, "src-bucket")
    ObjectStorage.create_bucket(os, "dst-bucket")
    ObjectStorage.put_object(os, "src-bucket", "file", "cross-bucket", "image/png")

    assert :ok = ObjectStorage.copy_object(os, "src-bucket", "file", "dst-bucket", "file-copy")

    assert {:ok, %{data: "cross-bucket", content_type: "image/png"}} =
             ObjectStorage.get_object(os, "dst-bucket", "file-copy")
  end

  test "copy to same bucket and same key is a no-op success", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    ObjectStorage.put_object(os, "b", "k", "original")

    assert :ok = ObjectStorage.copy_object(os, "b", "k", "b", "k")
    assert {:ok, %{data: "original"}} = ObjectStorage.get_object(os, "b", "k")
  end

  test "copy fails when source bucket doesn't exist", %{os: os} do
    ObjectStorage.create_bucket(os, "dst")

    assert {:error, :src_bucket_not_found} =
             ObjectStorage.copy_object(os, "ghost", "k", "dst", "k")
  end

  test "copy fails when destination bucket doesn't exist", %{os: os} do
    ObjectStorage.create_bucket(os, "src")
    ObjectStorage.put_object(os, "src", "k", "v")

    assert {:error, :dst_bucket_not_found} =
             ObjectStorage.copy_object(os, "src", "k", "ghost", "k")
  end

  test "copy fails when source key doesn't exist", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    assert {:error, :not_found} = ObjectStorage.copy_object(os, "b", "missing", "b", "dst")
  end

  # -------------------------------------------------------
  # Multipart upload
  # -------------------------------------------------------

  test "basic multipart upload and reassembly", %{os: os} do
    ObjectStorage.create_bucket(os, "b")

    assert {:ok, upload_id} =
             ObjectStorage.start_multipart(os, "b", "big-file.bin", "application/octet-stream", %{
               "source" => "upload"
             })

    assert is_binary(upload_id)

    assert :ok = ObjectStorage.upload_part(os, upload_id, 1, "AAA")
    assert :ok = ObjectStorage.upload_part(os, upload_id, 2, "BBB")
    assert :ok = ObjectStorage.upload_part(os, upload_id, 3, "CCC")

    assert :ok = ObjectStorage.complete_multipart(os, upload_id)

    assert {:ok, obj} = ObjectStorage.get_object(os, "b", "big-file.bin")
    assert obj.data == "AAABBBCCC"
    assert obj.content_type == "application/octet-stream"
    assert obj.metadata == %{"source" => "upload"}
    assert obj.size == 9
  end

  test "multipart parts can arrive out of order", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    {:ok, uid} = ObjectStorage.start_multipart(os, "b", "shuffled", "text/plain")

    ObjectStorage.upload_part(os, uid, 3, "third")
    ObjectStorage.upload_part(os, uid, 1, "first")
    ObjectStorage.upload_part(os, uid, 2, "second")

    ObjectStorage.complete_multipart(os, uid)

    assert {:ok, %{data: "firstsecondthird"}} = ObjectStorage.get_object(os, "b", "shuffled")
  end

  test "uploading the same part number overwrites previous data", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    {:ok, uid} = ObjectStorage.start_multipart(os, "b", "overwrite-part", "text/plain")

    ObjectStorage.upload_part(os, uid, 1, "old")
    ObjectStorage.upload_part(os, uid, 1, "new")
    ObjectStorage.upload_part(os, uid, 2, "end")

    ObjectStorage.complete_multipart(os, uid)

    assert {:ok, %{data: "newend"}} = ObjectStorage.get_object(os, "b", "overwrite-part")
  end

  test "complete_multipart with no parts returns error", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    {:ok, uid} = ObjectStorage.start_multipart(os, "b", "empty-multipart", "text/plain")

    assert {:error, :no_parts} = ObjectStorage.complete_multipart(os, uid)
  end

  test "upload_id is invalidated after completion", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    {:ok, uid} = ObjectStorage.start_multipart(os, "b", "done", "text/plain")
    ObjectStorage.upload_part(os, uid, 1, "x")
    ObjectStorage.complete_multipart(os, uid)

    assert {:error, :not_found} = ObjectStorage.upload_part(os, uid, 2, "y")
    assert {:error, :not_found} = ObjectStorage.complete_multipart(os, uid)
  end

  test "start_multipart on non-existent bucket", %{os: os} do
    assert {:error, :bucket_not_found} = ObjectStorage.start_multipart(os, "nope", "k")
  end

  test "upload_part with unknown upload_id", %{os: os} do
    assert {:error, :not_found} = ObjectStorage.upload_part(os, "bogus-id", 1, "data")
  end

  test "complete_multipart with unknown upload_id", %{os: os} do
    assert {:error, :not_found} = ObjectStorage.complete_multipart(os, "bogus-id")
  end

  # -------------------------------------------------------
  # Abort multipart
  # -------------------------------------------------------

  test "abort cleans up and invalidates the upload", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    {:ok, uid} = ObjectStorage.start_multipart(os, "b", "aborted", "text/plain")
    ObjectStorage.upload_part(os, uid, 1, "partial")

    assert :ok = ObjectStorage.abort_multipart(os, uid)

    # upload_id is now invalid
    assert {:error, :not_found} = ObjectStorage.upload_part(os, uid, 2, "more")
    assert {:error, :not_found} = ObjectStorage.complete_multipart(os, uid)

    # Object was never created
    assert {:error, :not_found} = ObjectStorage.get_object(os, "b", "aborted")
  end

  test "abort unknown upload_id returns error", %{os: os} do
    assert {:error, :not_found} = ObjectStorage.abort_multipart(os, "bogus-id")
  end

  # -------------------------------------------------------
  # Persistence across restarts
  # -------------------------------------------------------

  test "objects survive a GenServer restart", %{os: os, tmp_dir: tmp_dir} do
    ObjectStorage.create_bucket(os, "persist")
    ObjectStorage.put_object(os, "persist", "key", "durable-data", "text/plain", %{"x" => "y"})

    # Stop the GenServer
    GenServer.stop(os)

    # Restart with the same root_dir
    {:ok, pid2} = ObjectStorage.start_link(root_dir: tmp_dir)

    assert {:ok, ["persist"]} = ObjectStorage.list_buckets(pid2)
    assert {:ok, obj} = ObjectStorage.get_object(pid2, "persist", "key")
    assert obj.data == "durable-data"
    assert obj.content_type == "text/plain"
    assert obj.metadata == %{"x" => "y"}
  end

  # -------------------------------------------------------
  # Concurrent multipart uploads
  # -------------------------------------------------------

  test "multiple concurrent multipart uploads don't interfere", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    {:ok, uid1} = ObjectStorage.start_multipart(os, "b", "file-a", "text/plain")
    {:ok, uid2} = ObjectStorage.start_multipart(os, "b", "file-b", "text/plain")

    assert uid1 != uid2

    ObjectStorage.upload_part(os, uid1, 1, "A1")
    ObjectStorage.upload_part(os, uid2, 1, "B1")
    ObjectStorage.upload_part(os, uid1, 2, "A2")
    ObjectStorage.upload_part(os, uid2, 2, "B2")

    ObjectStorage.complete_multipart(os, uid1)
    ObjectStorage.complete_multipart(os, uid2)

    assert {:ok, %{data: "A1A2"}} = ObjectStorage.get_object(os, "b", "file-a")
    assert {:ok, %{data: "B1B2"}} = ObjectStorage.get_object(os, "b", "file-b")
  end

  test "a server started with :name is reachable through its registered name", %{tmp_dir: tmp_dir} do
    name = :"object_storage_named_#{System.unique_integer([:positive])}"
    root = Path.join(tmp_dir, "named-root")

    {:ok, named_pid} = ObjectStorage.start_link(root_dir: root, name: name)
    assert Process.whereis(name) == named_pid

    assert :ok = ObjectStorage.create_bucket(name, "via-name")
    assert :ok = ObjectStorage.put_object(name, "via-name", "k", "payload")
    assert {:ok, ["via-name"]} = ObjectStorage.list_buckets(name)
    assert {:ok, %{data: "payload"}} = ObjectStorage.get_object(name, "via-name", "k")

    GenServer.stop(name)
  end

  test "a completed upload_id cannot be aborted or replayed into a second object", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    {:ok, uid} = ObjectStorage.start_multipart(os, "b", "once.bin", "text/plain")
    assert :ok = ObjectStorage.upload_part(os, uid, 1, "only")
    assert :ok = ObjectStorage.complete_multipart(os, uid)

    assert {:error, :not_found} = ObjectStorage.abort_multipart(os, uid)
    assert {:error, :not_found} = ObjectStorage.upload_part(os, uid, 2, "extra")
    assert {:error, :not_found} = ObjectStorage.complete_multipart(os, uid)

    # The stored object must reflect exactly the one completion, not a replayed second one.
    assert {:ok, obj} = ObjectStorage.get_object(os, "b", "once.bin")
    assert obj.data == "only"
    assert obj.size == 4
  end

  test "start_multipart defaults content_type to octet-stream and metadata to empty", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    {:ok, uid} = ObjectStorage.start_multipart(os, "b", "defaults.bin")
    assert :ok = ObjectStorage.upload_part(os, uid, 1, "body")
    assert :ok = ObjectStorage.complete_multipart(os, uid)

    assert {:ok, obj} = ObjectStorage.get_object(os, "b", "defaults.bin")
    assert obj.content_type == "application/octet-stream"
    assert obj.metadata == %{}
  end

  test "max_keys limits the prefix-filtered result to the lexicographically first keys", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    ObjectStorage.put_object(os, "b", "a/3", "")
    ObjectStorage.put_object(os, "b", "a/1", "")
    ObjectStorage.put_object(os, "b", "a/2", "")
    ObjectStorage.put_object(os, "b", "b/1", "")

    assert {:ok, objects} = ObjectStorage.list_objects(os, "b", prefix: "a/", max_keys: 2)
    assert Enum.map(objects, & &1.key) == ["a/1", "a/2"]

    assert {:ok, all} = ObjectStorage.list_objects(os, "b", prefix: "a/")
    assert Enum.map(all, & &1.key) == ["a/1", "a/2", "a/3"]
  end

  test "put_object defaults metadata to an empty map", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    assert :ok = ObjectStorage.put_object(os, "b", "k", "v", "text/plain")

    assert {:ok, obj} = ObjectStorage.get_object(os, "b", "k")
    assert obj.metadata == %{}
    assert obj.content_type == "text/plain"
  end

  test "non-string bucket names are rejected as invalid", %{os: os} do
    assert {:error, :invalid_name} = ObjectStorage.create_bucket(os, :atom_bucket)
    assert {:error, :invalid_name} = ObjectStorage.create_bucket(os, 123)
    assert {:ok, []} = ObjectStorage.list_buckets(os)
  end
end
```
