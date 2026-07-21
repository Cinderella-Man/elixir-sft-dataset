# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule TtlObjectStorage do
  @moduledoc """
  An S3-like, in-memory object store with lifecycle time-to-live (TTL) expiration.

  Objects may carry a TTL expressed in milliseconds (or the atom `:infinity`),
  measured from the moment of the `put_object/5` or `set_ttl/4` call. Once at
  least its TTL has elapsed, an object is considered *expired*.

  Expiration is **lazy**: an expired object is treated as absent and is removed
  the moment it is next touched (e.g. via `get_object/3`). In addition,
  `purge_expired/1` provides an explicit bulk sweep that reclaims all currently
  expired objects across every bucket.

  Storage lives entirely in process memory and does not survive a restart.

  ## State

  Internally the server keeps a map of bucket name to a map of key to object.
  Each object records its binary `data`, its `size`, a `last_modified`
  `DateTime`, and an `expires_at` deadline expressed on the monotonic clock
  (or `:infinity`). The monotonic clock is used for expiration decisions so
  that wall-clock adjustments cannot affect TTL semantics.
  """

  use GenServer

  @typedoc "A registered process name or pid used to address the server."
  @type server :: GenServer.server()

  @typedoc "A time-to-live in milliseconds, or `:infinity` to never expire."
  @type ttl :: pos_integer() | :infinity

  # `\A`/`\z` (not `^`/`$`) so that a trailing newline cannot sneak past the anchors.
  @name_regex ~r/\A[a-z0-9.-]+\z/

  ## Public API

  @doc """
  Start the object store process.

  Options:

    * `:name` — an optional name under which to register the process.
    * `:default_ttl_ms` — a positive integer number of milliseconds, or
      `:infinity` (the default), applied to any `put_object/5` that does not
      specify its own `:ttl_ms`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    default_ttl = Keyword.get(opts, :default_ttl_ms, :infinity)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, %{default_ttl_ms: default_ttl}, gen_opts)
  end

  @doc """
  Create a bucket named `name`.

  Returns `:ok` on success, `{:error, :already_exists}` if the bucket already
  exists, or `{:error, :invalid_name}` if `name` is not a non-empty string of
  lowercase alphanumeric characters, hyphens, and dots.
  """
  @spec create_bucket(server(), String.t()) ::
          :ok | {:error, :already_exists | :invalid_name}
  def create_bucket(server, name) do
    GenServer.call(server, {:create_bucket, name})
  end

  @doc """
  List all bucket names, sorted lexicographically.
  """
  @spec list_buckets(server()) :: {:ok, [String.t()]}
  def list_buckets(server) do
    GenServer.call(server, :list_buckets)
  end

  @doc """
  Delete the bucket named `name`.

  The bucket is deleted only if it holds no live (unexpired) objects; expired
  objects are ignored and do not block deletion. Returns `:ok`,
  `{:error, :not_found}` if the bucket does not exist, or
  `{:error, :not_empty}` if it still contains at least one live object.
  """
  @spec delete_bucket(server(), String.t()) ::
          :ok | {:error, :not_found | :not_empty}
  def delete_bucket(server, name) do
    GenServer.call(server, {:delete_bucket, name})
  end

  @doc """
  Store `data` (a binary) under `key` in `bucket`, overwriting any existing
  object with the same key and resetting its TTL.

  Options:

    * `:ttl_ms` — a positive integer, or `:infinity`. If omitted, the server's
      `:default_ttl_ms` applies.

  Returns `:ok`, or `{:error, :bucket_not_found}`.
  """
  @spec put_object(server(), String.t(), String.t(), binary(), keyword()) ::
          :ok | {:error, :bucket_not_found}
  def put_object(server, bucket, key, data, opts \\ []) when is_binary(data) do
    GenServer.call(server, {:put_object, bucket, key, data, opts})
  end

  @doc """
  Retrieve the live object stored under `key` in `bucket`.

  Returns `{:ok, %{data: binary, size: integer, last_modified: DateTime.t()}}`,
  `{:error, :bucket_not_found}` if the bucket is missing, or
  `{:error, :not_found}` if the key does not exist or has expired. An expired
  object is removed as part of this call (lazy expiration).
  """
  @spec get_object(server(), String.t(), String.t()) ::
          {:ok, %{data: binary(), size: non_neg_integer(), last_modified: DateTime.t()}}
          | {:error, :bucket_not_found | :not_found}
  def get_object(server, bucket, key) do
    GenServer.call(server, {:get_object, bucket, key})
  end

  @doc """
  Remove the object stored under `key` in `bucket`.

  Idempotent: returns `:ok` even if the key does not exist. Returns
  `{:error, :bucket_not_found}` if the bucket is missing.
  """
  @spec delete_object(server(), String.t(), String.t()) ::
          :ok | {:error, :bucket_not_found}
  def delete_object(server, bucket, key) do
    GenServer.call(server, {:delete_object, bucket, key})
  end

  @doc """
  List the live objects in `bucket`, excluding expired ones, sorted
  lexicographically by key.

  Returns `{:ok, [%{key: string, size: integer, last_modified: DateTime.t()}]}`,
  or `{:error, :bucket_not_found}`.
  """
  @spec list_objects(server(), String.t()) ::
          {:ok, [%{key: String.t(), size: non_neg_integer(), last_modified: DateTime.t()}]}
          | {:error, :bucket_not_found}
  def list_objects(server, bucket) do
    GenServer.call(server, {:list_objects, bucket})
  end

  @doc """
  Reset the TTL of an existing live object under `key` in `bucket`.

  `ttl_ms` is a positive integer or `:infinity`, measured from now. Returns
  `:ok`, `{:error, :bucket_not_found}` if the bucket is missing, or
  `{:error, :not_found}` if the key does not exist or has already expired.
  """
  @spec set_ttl(server(), String.t(), String.t(), ttl()) ::
          :ok | {:error, :bucket_not_found | :not_found}
  def set_ttl(server, bucket, key, ttl_ms) do
    GenServer.call(server, {:set_ttl, bucket, key, ttl_ms})
  end

  @doc """
  Sweep every bucket and permanently remove all currently expired objects.

  Returns `{:ok, count}` where `count` is the number of objects removed.
  """
  @spec purge_expired(server()) :: {:ok, non_neg_integer()}
  def purge_expired(server) do
    GenServer.call(server, :purge_expired)
  end

  ## GenServer callbacks

  @impl true
  @spec init(map()) :: {:ok, map()}
  def init(%{default_ttl_ms: default_ttl}) do
    {:ok, %{default_ttl_ms: default_ttl, buckets: %{}}}
  end

  @impl true
  def handle_call({:create_bucket, name}, _from, state) do
    cond do
      not valid_name?(name) ->
        {:reply, {:error, :invalid_name}, state}

      Map.has_key?(state.buckets, name) ->
        {:reply, {:error, :already_exists}, state}

      true ->
        buckets = Map.put(state.buckets, name, %{})
        {:reply, :ok, %{state | buckets: buckets}}
    end
  end

  def handle_call(:list_buckets, _from, state) do
    {:reply, {:ok, Enum.sort(Map.keys(state.buckets))}, state}
  end

  def handle_call({:delete_bucket, name}, _from, state) do
    case Map.fetch(state.buckets, name) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, objects} ->
        now = now_ms()

        if Enum.any?(objects, fn {_key, obj} -> not expired?(obj, now) end) do
          {:reply, {:error, :not_empty}, state}
        else
          {:reply, :ok, %{state | buckets: Map.delete(state.buckets, name)}}
        end
    end
  end

  def handle_call({:put_object, bucket, key, data, opts}, _from, state) do
    case Map.fetch(state.buckets, bucket) do
      :error ->
        {:reply, {:error, :bucket_not_found}, state}

      {:ok, objects} ->
        ttl = Keyword.get(opts, :ttl_ms, state.default_ttl_ms)
        now = now_ms()

        object = %{
          data: data,
          size: byte_size(data),
          last_modified: DateTime.utc_now(),
          expires_at: compute_expires_at(ttl, now)
        }

        objects = Map.put(objects, key, object)
        {:reply, :ok, put_bucket(state, bucket, objects)}
    end
  end

  def handle_call({:get_object, bucket, key}, _from, state) do
    case Map.fetch(state.buckets, bucket) do
      :error ->
        {:reply, {:error, :bucket_not_found}, state}

      {:ok, objects} ->
        now = now_ms()

        case Map.fetch(objects, key) do
          {:ok, obj} ->
            if expired?(obj, now) do
              objects = Map.delete(objects, key)
              {:reply, {:error, :not_found}, put_bucket(state, bucket, objects)}
            else
              reply = {:ok, Map.take(obj, [:data, :size, :last_modified])}
              {:reply, reply, state}
            end

          :error ->
            {:reply, {:error, :not_found}, state}
        end
    end
  end

  def handle_call({:delete_object, bucket, key}, _from, state) do
    case Map.fetch(state.buckets, bucket) do
      :error ->
        {:reply, {:error, :bucket_not_found}, state}

      {:ok, objects} ->
        objects = Map.delete(objects, key)
        {:reply, :ok, put_bucket(state, bucket, objects)}
    end
  end

  def handle_call({:list_objects, bucket}, _from, state) do
    case Map.fetch(state.buckets, bucket) do
      :error ->
        {:reply, {:error, :bucket_not_found}, state}

      {:ok, objects} ->
        now = now_ms()

        listing =
          objects
          |> Enum.reject(fn {_key, obj} -> expired?(obj, now) end)
          |> Enum.map(fn {key, obj} ->
            %{key: key, size: obj.size, last_modified: obj.last_modified}
          end)
          |> Enum.sort_by(& &1.key)

        {:reply, {:ok, listing}, state}
    end
  end

  def handle_call({:set_ttl, bucket, key, ttl_ms}, _from, state) do
    case Map.fetch(state.buckets, bucket) do
      :error ->
        {:reply, {:error, :bucket_not_found}, state}

      {:ok, objects} ->
        now = now_ms()

        case Map.fetch(objects, key) do
          {:ok, obj} ->
            if expired?(obj, now) do
              objects = Map.delete(objects, key)
              {:reply, {:error, :not_found}, put_bucket(state, bucket, objects)}
            else
              obj = %{obj | expires_at: compute_expires_at(ttl_ms, now)}
              objects = Map.put(objects, key, obj)
              {:reply, :ok, put_bucket(state, bucket, objects)}
            end

          :error ->
            {:reply, {:error, :not_found}, state}
        end
    end
  end

  def handle_call(:purge_expired, _from, state) do
    now = now_ms()

    {buckets, removed} =
      Enum.reduce(state.buckets, {%{}, 0}, fn {name, objects}, {acc, count} ->
        live = Enum.reject(objects, fn {_key, obj} -> expired?(obj, now) end)
        removed = map_size(objects) - length(live)
        {Map.put(acc, name, Map.new(live)), count + removed}
      end)

    {:reply, {:ok, removed}, %{state | buckets: buckets}}
  end

  ## Internal helpers

  @spec put_bucket(map(), String.t(), map()) :: map()
  defp put_bucket(state, bucket, objects) do
    %{state | buckets: Map.put(state.buckets, bucket, objects)}
  end

  @spec valid_name?(term()) :: boolean()
  defp valid_name?(name) when is_binary(name) and name != "" do
    Regex.match?(@name_regex, name)
  end

  defp valid_name?(_name), do: false

  @spec now_ms() :: integer()
  defp now_ms, do: System.monotonic_time(:millisecond)

  @spec compute_expires_at(ttl(), integer()) :: number() | :infinity
  defp compute_expires_at(:infinity, _now), do: :infinity
  defp compute_expires_at(ttl_ms, now), do: now + ttl_ms

  @spec expired?(map(), integer()) :: boolean()
  defp expired?(%{expires_at: :infinity}, _now), do: false
  defp expired?(%{expires_at: expires_at}, now), do: now >= expires_at
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule TtlObjectStorageTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = TtlObjectStorage.start_link([])
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    %{os: pid}
  end

  # -------------------------------------------------------
  # Buckets
  # -------------------------------------------------------

  test "create, list, and delete buckets", %{os: os} do
    # TODO
  end

  test "invalid and duplicate bucket names", %{os: os} do
    assert {:error, :invalid_name} = TtlObjectStorage.create_bucket(os, "")
    assert {:error, :invalid_name} = TtlObjectStorage.create_bucket(os, "UPPER")
    assert :ok = TtlObjectStorage.create_bucket(os, "a-b.c")
    assert {:error, :already_exists} = TtlObjectStorage.create_bucket(os, "a-b.c")
  end

  test "delete_bucket returns not_found / not_empty", %{os: os} do
    assert {:error, :not_found} = TtlObjectStorage.delete_bucket(os, "ghost")

    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v")
    assert {:error, :not_empty} = TtlObjectStorage.delete_bucket(os, "b")
  end

  test "list_buckets is empty for a fresh server", %{os: os} do
    assert {:ok, []} = TtlObjectStorage.list_buckets(os)
  end

  test "non-string bucket names are rejected as invalid", %{os: os} do
    assert {:error, :invalid_name} = TtlObjectStorage.create_bucket(os, :atom)
    assert {:error, :invalid_name} = TtlObjectStorage.create_bucket(os, 123)
    assert {:error, :invalid_name} = TtlObjectStorage.create_bucket(os, "has space")
  end

  # -------------------------------------------------------
  # Basic put / get
  # -------------------------------------------------------

  test "put and get with default (infinite) ttl", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    assert :ok = TtlObjectStorage.put_object(os, "b", "k", "hello")

    assert {:ok, obj} = TtlObjectStorage.get_object(os, "b", "k")
    assert obj.data == "hello"
    assert obj.size == byte_size("hello")
    assert %DateTime{} = obj.last_modified
  end

  test "put to a missing bucket and get errors", %{os: os} do
    assert {:error, :bucket_not_found} = TtlObjectStorage.put_object(os, "nope", "k", "v")
    assert {:error, :bucket_not_found} = TtlObjectStorage.get_object(os, "nope", "k")

    TtlObjectStorage.create_bucket(os, "b")
    assert {:error, :not_found} = TtlObjectStorage.get_object(os, "b", "missing")
  end

  test "an object with a live ttl is still readable", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v", ttl_ms: 5_000)
    assert {:ok, %{data: "v"}} = TtlObjectStorage.get_object(os, "b", "k")
  end

  test "put and get an empty binary reports a zero size", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    assert :ok = TtlObjectStorage.put_object(os, "b", "k", "")
    assert {:ok, %{data: "", size: 0}} = TtlObjectStorage.get_object(os, "b", "k")
  end

  # -------------------------------------------------------
  # Expiration
  # -------------------------------------------------------

  test "an expired object reads as not_found", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v", ttl_ms: 40)
    Process.sleep(120)
    assert {:error, :not_found} = TtlObjectStorage.get_object(os, "b", "k")
  end

  test "reading an expired object removes it lazily", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v", ttl_ms: 40)
    Process.sleep(120)
    # The lazy read should have deleted it, so a later purge finds nothing.
    assert {:error, :not_found} = TtlObjectStorage.get_object(os, "b", "k")
    assert {:ok, 0} = TtlObjectStorage.purge_expired(os)
  end

  test "list_objects excludes expired objects and is sorted", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "keep", "1", ttl_ms: 5_000)
    :ok = TtlObjectStorage.put_object(os, "b", "gone", "22", ttl_ms: 40)
    Process.sleep(120)

    assert {:ok, [obj]} = TtlObjectStorage.list_objects(os, "b")
    assert obj.key == "keep"
    assert obj.size == 1
    assert %DateTime{} = obj.last_modified
  end

  test "list_objects reports bucket_not_found and empty buckets", %{os: os} do
    assert {:error, :bucket_not_found} = TtlObjectStorage.list_objects(os, "nope")
    TtlObjectStorage.create_bucket(os, "b")
    assert {:ok, []} = TtlObjectStorage.list_objects(os, "b")
  end

  test "purge_expired removes expired objects and reports the count", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "a", "x", ttl_ms: 40)
    :ok = TtlObjectStorage.put_object(os, "b", "b", "y", ttl_ms: 40)
    :ok = TtlObjectStorage.put_object(os, "b", "c", "z", ttl_ms: 5_000)
    Process.sleep(120)

    assert {:ok, 2} = TtlObjectStorage.purge_expired(os)
    assert {:ok, [%{key: "c"}]} = TtlObjectStorage.list_objects(os, "b")
  end

  test "purge_expired counts across multiple buckets", %{os: os} do
    TtlObjectStorage.create_bucket(os, "one")
    TtlObjectStorage.create_bucket(os, "two")
    :ok = TtlObjectStorage.put_object(os, "one", "k", "v", ttl_ms: 40)
    :ok = TtlObjectStorage.put_object(os, "two", "k", "v", ttl_ms: 40)
    :ok = TtlObjectStorage.put_object(os, "two", "live", "v", ttl_ms: 5_000)
    Process.sleep(120)

    assert {:ok, 2} = TtlObjectStorage.purge_expired(os)
    assert {:ok, []} = TtlObjectStorage.list_objects(os, "one")
    assert {:ok, [%{key: "live"}]} = TtlObjectStorage.list_objects(os, "two")
  end

  test "purge_expired returns zero when nothing has expired", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v", ttl_ms: 5_000)
    assert {:ok, 0} = TtlObjectStorage.purge_expired(os)
    assert {:ok, [%{key: "k"}]} = TtlObjectStorage.list_objects(os, "b")
  end

  test "delete_bucket succeeds when only expired objects remain", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v", ttl_ms: 40)
    Process.sleep(120)
    assert :ok = TtlObjectStorage.delete_bucket(os, "b")
    assert {:ok, []} = TtlObjectStorage.list_buckets(os)
  end

  # -------------------------------------------------------
  # set_ttl
  # -------------------------------------------------------

  test "set_ttl extends the life of an object", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v", ttl_ms: 40)
    assert :ok = TtlObjectStorage.set_ttl(os, "b", "k", 5_000)
    Process.sleep(120)
    assert {:ok, %{data: "v"}} = TtlObjectStorage.get_object(os, "b", "k")
  end

  test "set_ttl can shorten an object's life", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v", ttl_ms: :infinity)
    assert :ok = TtlObjectStorage.set_ttl(os, "b", "k", 40)
    Process.sleep(120)
    assert {:error, :not_found} = TtlObjectStorage.get_object(os, "b", "k")
  end

  test "set_ttl to infinity keeps a previously expiring object alive", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v", ttl_ms: 5_000)
    assert :ok = TtlObjectStorage.set_ttl(os, "b", "k", :infinity)
    Process.sleep(120)
    assert {:ok, %{data: "v"}} = TtlObjectStorage.get_object(os, "b", "k")
  end

  test "set_ttl errors for missing bucket or key", %{os: os} do
    assert {:error, :bucket_not_found} = TtlObjectStorage.set_ttl(os, "nope", "k", 100)
    TtlObjectStorage.create_bucket(os, "b")
    assert {:error, :not_found} = TtlObjectStorage.set_ttl(os, "b", "missing", 100)
  end

  test "set_ttl on an already expired key errors as not_found", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v", ttl_ms: 40)
    Process.sleep(120)
    assert {:error, :not_found} = TtlObjectStorage.set_ttl(os, "b", "k", 5_000)
  end

  # -------------------------------------------------------
  # Overwrite resets ttl
  # -------------------------------------------------------

  test "overwriting an object resets its ttl", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "old", ttl_ms: 40)
    :ok = TtlObjectStorage.put_object(os, "b", "k", "new", ttl_ms: 5_000)
    Process.sleep(120)
    assert {:ok, %{data: "new"}} = TtlObjectStorage.get_object(os, "b", "k")
  end

  # -------------------------------------------------------
  # delete_object
  # -------------------------------------------------------

  test "delete_object is idempotent and reports bucket_not_found", %{os: os} do
    assert {:error, :bucket_not_found} = TtlObjectStorage.delete_object(os, "nope", "k")
    TtlObjectStorage.create_bucket(os, "b")
    assert :ok = TtlObjectStorage.delete_object(os, "b", "never")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v")
    assert :ok = TtlObjectStorage.delete_object(os, "b", "k")
    assert {:error, :not_found} = TtlObjectStorage.get_object(os, "b", "k")
  end

  # -------------------------------------------------------
  # Server default ttl / naming
  # -------------------------------------------------------

  test "server default_ttl_ms applies when no per-object ttl is given", %{os: _os} do
    {:ok, s2} = TtlObjectStorage.start_link(default_ttl_ms: 40)
    TtlObjectStorage.create_bucket(s2, "b")
    :ok = TtlObjectStorage.put_object(s2, "b", "k", "v")
    Process.sleep(120)
    assert {:error, :not_found} = TtlObjectStorage.get_object(s2, "b", "k")
    GenServer.stop(s2)
  end

  test "a per-object ttl overrides the server default_ttl_ms", %{os: _os} do
    {:ok, s2} = TtlObjectStorage.start_link(default_ttl_ms: 40)
    TtlObjectStorage.create_bucket(s2, "b")
    :ok = TtlObjectStorage.put_object(s2, "b", "k", "v", ttl_ms: 5_000)
    Process.sleep(120)
    assert {:ok, %{data: "v"}} = TtlObjectStorage.get_object(s2, "b", "k")
    GenServer.stop(s2)
  end

  test "the server can be registered and addressed by name", %{os: _os} do
    name = :"ttl_named_#{System.unique_integer([:positive])}"
    {:ok, pid} = TtlObjectStorage.start_link(name: name)
    assert :ok = TtlObjectStorage.create_bucket(name, "b")
    :ok = TtlObjectStorage.put_object(name, "b", "k", "v")

    assert {:ok, %{data: "v"}} =
             TtlObjectStorage.get_object(name, "k" |> then(fn _ -> "b" end), "k")

    GenServer.stop(pid)
  end

  test "a bucket name with a trailing newline is rejected as invalid", %{os: os} do
    assert {:error, :invalid_name} = TtlObjectStorage.create_bucket(os, "abc\n")
    assert {:error, :invalid_name} = TtlObjectStorage.create_bucket(os, "a-b.c\n")
    assert {:ok, []} = TtlObjectStorage.list_buckets(os)
  end

  test "bucket names with underscores or slashes are invalid, digits are valid", %{os: os} do
    assert {:error, :invalid_name} = TtlObjectStorage.create_bucket(os, "a_b")
    assert {:error, :invalid_name} = TtlObjectStorage.create_bucket(os, "a/b")
    assert :ok = TtlObjectStorage.create_bucket(os, "a1-b.2")
    assert {:ok, ["a1-b.2"]} = TtlObjectStorage.list_buckets(os)
  end

  test "list_objects sorts several live keys lexicographically", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "delta", "4")
    :ok = TtlObjectStorage.put_object(os, "b", "alpha", "1")
    :ok = TtlObjectStorage.put_object(os, "b", "Charlie", "3")
    :ok = TtlObjectStorage.put_object(os, "b", "bravo", "2")

    assert {:ok, listing} = TtlObjectStorage.list_objects(os, "b")
    assert Enum.map(listing, & &1.key) == ["Charlie", "alpha", "bravo", "delta"]
    assert Enum.map(listing, & &1.size) == [1, 1, 1, 1]
  end

  # -------------------------------------------------------
  # Default ttl outlives explicit ttls
  # -------------------------------------------------------

  # Polls the object until it reads as absent, or until the deadline passes.
  defp await_expiry(server, bucket, key, deadline_ms) do
    case TtlObjectStorage.get_object(server, bucket, key) do
      {:error, :not_found} ->
        :expired

      _live ->
        if System.monotonic_time(:millisecond) >= deadline_ms do
          :still_live
        else
          Process.sleep(10)
          await_expiry(server, bucket, key, deadline_ms)
        end
    end
  end

  test "an object written with the default ttl survives a far longer explicit ttl",
       %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    # No :ttl_ms, so the server default (documented as :infinity) applies.
    :ok = TtlObjectStorage.put_object(os, "b", "keeper", "v")
    :ok = TtlObjectStorage.put_object(os, "b", "canary", "v", ttl_ms: 400)

    deadline = System.monotonic_time(:millisecond) + 6_000
    assert :expired = await_expiry(os, "b", "canary", deadline)

    # Well past the canary's lifetime, the default-ttl object is untouched by
    # both lazy reads and the bulk sweep, and still blocks bucket deletion.
    assert {:ok, %{data: "v"}} = TtlObjectStorage.get_object(os, "b", "keeper")
    assert {:ok, 0} = TtlObjectStorage.purge_expired(os)
    assert {:ok, [%{key: "keeper"}]} = TtlObjectStorage.list_objects(os, "b")
    assert {:error, :not_empty} = TtlObjectStorage.delete_bucket(os, "b")
  end
end
```
