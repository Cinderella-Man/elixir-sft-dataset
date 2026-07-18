# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

  @spec valid_name?(term()) :: boolean()
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

## Test harness — implement the `# TODO` test

```elixir
defmodule VersionedObjectStorageTest do
  use ExUnit.Case, async: false

  # Build a per-run unique root so concurrent OS processes sharing a CWD do not
  # collide. System.pid/0 separates BEAM instances; the random suffix guards
  # against OS pid reuse. Cleanup uses the non-raising rm_rf/1.
  setup do
    unique =
      "#{System.pid()}-#{System.unique_integer([:positive])}-" <>
        Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)

    tmp_dir = Path.expand(Path.join(["tmp", "versioned_object_storage_test", unique]))
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf(tmp_dir) end)

    {:ok, pid} = VersionedObjectStorage.start_link(root_dir: tmp_dir)
    %{os: pid, tmp_dir: tmp_dir}
  end

  # -------------------------------------------------------
  # Buckets
  # -------------------------------------------------------

  test "create and list buckets sorted", %{os: os} do
    assert :ok = VersionedObjectStorage.create_bucket(os, "beta")
    assert :ok = VersionedObjectStorage.create_bucket(os, "alpha")
    assert {:ok, ["alpha", "beta"]} = VersionedObjectStorage.list_buckets(os)
  end

  test "invalid and duplicate bucket names", %{os: os} do
    assert {:error, :invalid_name} = VersionedObjectStorage.create_bucket(os, "")
    assert {:error, :invalid_name} = VersionedObjectStorage.create_bucket(os, "UPPER")
    assert {:error, :invalid_name} = VersionedObjectStorage.create_bucket(os, "has space")
    assert :ok = VersionedObjectStorage.create_bucket(os, "my-bucket.v2")
    assert {:error, :already_exists} = VersionedObjectStorage.create_bucket(os, "my-bucket.v2")
  end

  test "list_buckets is empty for a fresh store", %{os: os} do
    assert {:ok, []} = VersionedObjectStorage.list_buckets(os)
  end

  test "underscore and slash bucket names are rejected", %{os: os} do
    assert {:error, :invalid_name} = VersionedObjectStorage.create_bucket(os, "bad_name")
    assert {:error, :invalid_name} = VersionedObjectStorage.create_bucket(os, "bad/name")
    assert {:error, :invalid_name} = VersionedObjectStorage.create_bucket(os, "MiXeD")
  end

  test "buckets are isolated from one another", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "one")
    VersionedObjectStorage.create_bucket(os, "two")
    VersionedObjectStorage.put_object(os, "one", "k", "in-one")

    assert {:ok, %{data: "in-one"}} = VersionedObjectStorage.get_object(os, "one", "k")
    assert {:error, :not_found} = VersionedObjectStorage.get_object(os, "two", "k")
    assert {:ok, []} = VersionedObjectStorage.list_objects(os, "two")
  end

  # -------------------------------------------------------
  # Put / get / versions
  # -------------------------------------------------------

  test "put returns a unique version id and get returns the latest version", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")

    assert {:ok, vid} = VersionedObjectStorage.put_object(os, "b", "k", "one", %{"n" => "1"})
    assert is_binary(vid)

    assert {:ok, obj} = VersionedObjectStorage.get_object(os, "b", "k")
    assert obj.data == "one"
    assert obj.metadata == %{"n" => "1"}
    assert obj.size == byte_size("one")
    assert obj.version_id == vid
    assert %DateTime{} = obj.last_modified
  end

  test "put_object defaults metadata to an empty map", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, _vid} = VersionedObjectStorage.put_object(os, "b", "k", "payload")

    assert {:ok, obj} = VersionedObjectStorage.get_object(os, "b", "k")
    assert obj.metadata == %{}
    assert obj.data == "payload"
  end

  test "each put creates a new retained version; get returns the newest", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, vid1} = VersionedObjectStorage.put_object(os, "b", "k", "one")
    {:ok, vid2} = VersionedObjectStorage.put_object(os, "b", "k", "two")

    assert vid1 != vid2

    assert {:ok, %{data: "two", version_id: ^vid2}} =
             VersionedObjectStorage.get_object(os, "b", "k")

    assert {:ok, versions} = VersionedObjectStorage.list_versions(os, "b", "k")
    assert length(versions) == 2

    # newest first
    assert [%{version_id: ^vid2, is_delete_marker: false} | _] = versions
  end

  test "list_versions is ordered strictly newest first", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, v1} = VersionedObjectStorage.put_object(os, "b", "k", "one")
    {:ok, v2} = VersionedObjectStorage.put_object(os, "b", "k", "two")
    {:ok, v3} = VersionedObjectStorage.put_object(os, "b", "k", "three")

    assert {:ok, versions} = VersionedObjectStorage.list_versions(os, "b", "k")
    assert Enum.map(versions, & &1.version_id) == [v3, v2, v1]
  end

  test "list_versions on a key with no versions returns empty list", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    assert {:ok, []} = VersionedObjectStorage.list_versions(os, "b", "ghost")
  end

  test "each version records its own size", %{os: os} do
    # TODO
  end

  test "get_object_version fetches a specific historical version", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, vid1} = VersionedObjectStorage.put_object(os, "b", "k", "one")
    {:ok, _vid2} = VersionedObjectStorage.put_object(os, "b", "k", "two")

    assert {:ok, v} = VersionedObjectStorage.get_object_version(os, "b", "k", vid1)
    assert v.data == "one"
    assert v.version_id == vid1
    assert v.is_delete_marker == false
  end

  test "get_object_version preserves per-version metadata", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, v1} = VersionedObjectStorage.put_object(os, "b", "k", "one", %{"tag" => "a"})
    {:ok, v2} = VersionedObjectStorage.put_object(os, "b", "k", "two", %{"tag" => "b"})

    assert {:ok, %{metadata: %{"tag" => "a"}}} =
             VersionedObjectStorage.get_object_version(os, "b", "k", v1)

    assert {:ok, %{metadata: %{"tag" => "b"}}} =
             VersionedObjectStorage.get_object_version(os, "b", "k", v2)
  end

  test "get_object_version on unknown version returns not_found", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    VersionedObjectStorage.put_object(os, "b", "k", "one")
    assert {:error, :not_found} = VersionedObjectStorage.get_object_version(os, "b", "k", "bogus")
  end

  # -------------------------------------------------------
  # Delete markers
  # -------------------------------------------------------

  test "delete_object writes a delete marker and hides the object", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, _} = VersionedObjectStorage.put_object(os, "b", "k", "one")

    assert {:ok, marker} = VersionedObjectStorage.delete_object(os, "b", "k")
    assert is_binary(marker)

    assert {:error, :not_found} = VersionedObjectStorage.get_object(os, "b", "k")

    assert {:ok, versions} = VersionedObjectStorage.list_versions(os, "b", "k")
    assert length(versions) == 2
    assert [%{version_id: ^marker, is_delete_marker: true, size: 0} | _] = versions

    assert {:ok, %{is_delete_marker: true, data: ""}} =
             VersionedObjectStorage.get_object_version(os, "b", "k", marker)
  end

  test "delete marker still hides the object after re-put then re-delete", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, _} = VersionedObjectStorage.put_object(os, "b", "k", "one")
    {:ok, _} = VersionedObjectStorage.delete_object(os, "b", "k")
    {:ok, _} = VersionedObjectStorage.put_object(os, "b", "k", "two")

    assert {:ok, %{data: "two"}} = VersionedObjectStorage.get_object(os, "b", "k")
    {:ok, _} = VersionedObjectStorage.delete_object(os, "b", "k")
    assert {:error, :not_found} = VersionedObjectStorage.get_object(os, "b", "k")

    assert {:ok, versions} = VersionedObjectStorage.list_versions(os, "b", "k")
    assert length(versions) == 4
  end

  test "delete_version permanently removes one version", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, vid1} = VersionedObjectStorage.put_object(os, "b", "k", "one")
    {:ok, _vid2} = VersionedObjectStorage.put_object(os, "b", "k", "two")

    assert :ok = VersionedObjectStorage.delete_version(os, "b", "k", vid1)
    assert {:ok, [one]} = VersionedObjectStorage.list_versions(os, "b", "k")
    refute one.version_id == vid1
    assert {:ok, %{data: "two"}} = VersionedObjectStorage.get_object(os, "b", "k")
  end

  test "delete_version of an old version leaves it unreadable afterward", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, vid1} = VersionedObjectStorage.put_object(os, "b", "k", "one")
    {:ok, _vid2} = VersionedObjectStorage.put_object(os, "b", "k", "two")

    assert :ok = VersionedObjectStorage.delete_version(os, "b", "k", vid1)

    assert {:error, :not_found} =
             VersionedObjectStorage.get_object_version(os, "b", "k", vid1)
  end

  test "delete_version is idempotent", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    assert :ok = VersionedObjectStorage.delete_version(os, "b", "never", "nope")
  end

  test "deleting the delete marker restores the previous version", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, _} = VersionedObjectStorage.put_object(os, "b", "k", "one")
    {:ok, _} = VersionedObjectStorage.put_object(os, "b", "k", "two")
    {:ok, marker} = VersionedObjectStorage.delete_object(os, "b", "k")

    assert {:error, :not_found} = VersionedObjectStorage.get_object(os, "b", "k")
    assert :ok = VersionedObjectStorage.delete_version(os, "b", "k", marker)
    assert {:ok, %{data: "two"}} = VersionedObjectStorage.get_object(os, "b", "k")
  end

  # -------------------------------------------------------
  # list_objects reflects current state
  # -------------------------------------------------------

  test "list_objects shows only live keys, sorted", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    VersionedObjectStorage.put_object(os, "b", "a", "1")
    VersionedObjectStorage.put_object(os, "b", "b", "22")
    VersionedObjectStorage.put_object(os, "b", "c", "333")
    VersionedObjectStorage.delete_object(os, "b", "b")

    assert {:ok, objs} = VersionedObjectStorage.list_objects(os, "b")
    assert Enum.map(objs, & &1.key) == ["a", "c"]

    assert Enum.all?(objs, fn o ->
             is_integer(o.size) and match?(%DateTime{}, o.last_modified)
           end)
  end

  test "list_objects reports the latest version id per key", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, _} = VersionedObjectStorage.put_object(os, "b", "k", "one")
    {:ok, latest} = VersionedObjectStorage.put_object(os, "b", "k", "two")

    assert {:ok, [%{key: "k", version_id: ^latest, size: 3}]} =
             VersionedObjectStorage.list_objects(os, "b")
  end

  test "list_objects on empty bucket returns empty list", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "empty")
    assert {:ok, []} = VersionedObjectStorage.list_objects(os, "empty")
  end

  # -------------------------------------------------------
  # Errors
  # -------------------------------------------------------

  test "operations on a missing bucket report bucket_not_found", %{os: os} do
    assert {:error, :bucket_not_found} = VersionedObjectStorage.put_object(os, "nope", "k", "v")
    assert {:error, :bucket_not_found} = VersionedObjectStorage.get_object(os, "nope", "k")
    assert {:error, :bucket_not_found} = VersionedObjectStorage.delete_object(os, "nope", "k")
    assert {:error, :bucket_not_found} = VersionedObjectStorage.list_versions(os, "nope", "k")
    assert {:error, :bucket_not_found} = VersionedObjectStorage.list_objects(os, "nope")
  end

  test "version operations on a missing bucket report bucket_not_found", %{os: os} do
    assert {:error, :bucket_not_found} =
             VersionedObjectStorage.get_object_version(os, "nope", "k", "vid")

    assert {:error, :bucket_not_found} =
             VersionedObjectStorage.delete_version(os, "nope", "k", "vid")
  end

  test "get on a key with no versions returns not_found", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    assert {:error, :not_found} = VersionedObjectStorage.get_object(os, "b", "missing")
  end

  # -------------------------------------------------------
  # Persistence
  # -------------------------------------------------------

  test "versions and restore survive a restart", %{os: os, tmp_dir: tmp_dir} do
    VersionedObjectStorage.create_bucket(os, "persist")
    {:ok, _} = VersionedObjectStorage.put_object(os, "persist", "k", "one", %{"x" => "y"})
    {:ok, _} = VersionedObjectStorage.put_object(os, "persist", "k", "two")
    {:ok, marker} = VersionedObjectStorage.delete_object(os, "persist", "k")

    GenServer.stop(os)
    {:ok, pid2} = VersionedObjectStorage.start_link(root_dir: tmp_dir)

    assert {:ok, ["persist"]} = VersionedObjectStorage.list_buckets(pid2)
    assert {:error, :not_found} = VersionedObjectStorage.get_object(pid2, "persist", "k")

    assert {:ok, versions} = VersionedObjectStorage.list_versions(pid2, "persist", "k")
    assert length(versions) == 3
    assert [%{is_delete_marker: true} | _] = versions

    assert :ok = VersionedObjectStorage.delete_version(pid2, "persist", "k", marker)
    assert {:ok, %{data: "two"}} = VersionedObjectStorage.get_object(pid2, "persist", "k")
  end

  test "an empty bucket survives a restart", %{os: os, tmp_dir: tmp_dir} do
    VersionedObjectStorage.create_bucket(os, "kept")

    GenServer.stop(os)
    {:ok, pid2} = VersionedObjectStorage.start_link(root_dir: tmp_dir)

    assert {:ok, ["kept"]} = VersionedObjectStorage.list_buckets(pid2)
    assert {:ok, []} = VersionedObjectStorage.list_objects(pid2, "kept")
  end

  test "metadata and version ids survive a restart", %{os: os, tmp_dir: tmp_dir} do
    VersionedObjectStorage.create_bucket(os, "meta")
    {:ok, vid} = VersionedObjectStorage.put_object(os, "meta", "k", "body", %{"a" => "b"})

    GenServer.stop(os)
    {:ok, pid2} = VersionedObjectStorage.start_link(root_dir: tmp_dir)

    assert {:ok, obj} = VersionedObjectStorage.get_object(pid2, "meta", "k")
    assert obj.version_id == vid
    assert obj.metadata == %{"a" => "b"}
    assert obj.data == "body"
  end

  test "start_link registers the process under the :name option", %{tmp_dir: tmp_dir} do
    name = :"vos_named_#{System.unique_integer([:positive])}"

    {:ok, _pid} =
      VersionedObjectStorage.start_link(root_dir: Path.join(tmp_dir, "named"), name: name)

    assert :ok = VersionedObjectStorage.create_bucket(name, "b")
    assert {:ok, _vid} = VersionedObjectStorage.put_object(name, "b", "k", "via-name")
    assert {:ok, ["b"]} = VersionedObjectStorage.list_buckets(name)
    assert {:ok, %{data: "via-name"}} = VersionedObjectStorage.get_object(name, "b", "k")
  end

  test "a permanently deleted version stays gone after a restart", %{os: os, tmp_dir: tmp_dir} do
    VersionedObjectStorage.create_bucket(os, "perm")
    {:ok, v1} = VersionedObjectStorage.put_object(os, "perm", "k", "one")
    {:ok, v2} = VersionedObjectStorage.put_object(os, "perm", "k", "two")
    assert :ok = VersionedObjectStorage.delete_version(os, "perm", "k", v1)

    GenServer.stop(os)
    {:ok, pid2} = VersionedObjectStorage.start_link(root_dir: tmp_dir)

    assert {:error, :not_found} = VersionedObjectStorage.get_object_version(pid2, "perm", "k", v1)
    assert {:ok, [%{version_id: ^v2}]} = VersionedObjectStorage.list_versions(pid2, "perm", "k")
    assert {:ok, %{data: "two"}} = VersionedObjectStorage.get_object(pid2, "perm", "k")
  end

  test "identical repeated puts still create distinct retained versions", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, v1} = VersionedObjectStorage.put_object(os, "b", "k", "same", %{"m" => "1"})
    {:ok, v2} = VersionedObjectStorage.put_object(os, "b", "k", "same", %{"m" => "1"})

    assert v1 != v2
    assert {:ok, versions} = VersionedObjectStorage.list_versions(os, "b", "k")
    assert Enum.map(versions, & &1.version_id) == [v2, v1]

    assert {:ok, %{data: "same", metadata: %{"m" => "1"}}} =
             VersionedObjectStorage.get_object_version(os, "b", "k", v1)
  end

  test "delete_object on a key with no versions returns a marker id", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")

    assert {:ok, marker} = VersionedObjectStorage.delete_object(os, "b", "ghost")
    assert is_binary(marker)

    assert {:ok, [%{version_id: ^marker, is_delete_marker: true, size: 0}]} =
             VersionedObjectStorage.list_versions(os, "b", "ghost")

    assert {:error, :not_found} = VersionedObjectStorage.get_object(os, "b", "ghost")
    assert {:ok, []} = VersionedObjectStorage.list_objects(os, "b")
  end

  test "delete_version with an unknown id leaves existing versions intact", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, v1} = VersionedObjectStorage.put_object(os, "b", "k", "one")

    assert :ok = VersionedObjectStorage.delete_version(os, "b", "k", "no-such-version")
    assert {:ok, [%{version_id: ^v1}]} = VersionedObjectStorage.list_versions(os, "b", "k")
    assert {:ok, %{data: "one"}} = VersionedObjectStorage.get_object(os, "b", "k")
  end

  test "a bucket recreated after a restart reports already_exists", %{os: os, tmp_dir: tmp_dir} do
    assert :ok = VersionedObjectStorage.create_bucket(os, "dup")

    GenServer.stop(os)
    {:ok, pid2} = VersionedObjectStorage.start_link(root_dir: tmp_dir)

    assert {:error, :already_exists} = VersionedObjectStorage.create_bucket(pid2, "dup")
    assert {:ok, ["dup"]} = VersionedObjectStorage.list_buckets(pid2)
  end
end
```
