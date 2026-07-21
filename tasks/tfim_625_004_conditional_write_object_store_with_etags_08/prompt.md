# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule ConditionalObjectStorage do
  @moduledoc """
  An S3-like, in-memory object store with optimistic concurrency control.

  Objects are grouped into named buckets and stored entirely in process
  memory (state is lost when the process stops). Every object carries an
  **ETag** — the lowercase, hex-encoded SHA-256 digest of the object's
  data. Identical data always produces the same ETag and different data
  produces a different ETag.

  Conditional requests mirror S3's `If-Match` / `If-None-Match`
  preconditions, enabling create-only writes, compare-and-swap updates,
  conditional deletes, and cache-revalidation reads.
  """

  use GenServer

  @type bucket :: String.t()
  @type key :: String.t()
  @type etag :: String.t()

  @typep object :: %{
           data: binary(),
           etag: etag(),
           size: non_neg_integer(),
           last_modified: DateTime.t()
         }

  @typep state :: %{buckets: %{optional(bucket()) => %{optional(key()) => object()}}}

  @name_regex ~r/\A[a-z0-9.-]+\z/

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Start the object store process.

  Accepts a `:name` option used to register the process; any other options
  are passed through to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, rest} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, rest, server_opts)
  end

  @doc """
  Create a bucket.

  Returns `:ok` on success, `{:error, :already_exists}` if the bucket is
  already present, or `{:error, :invalid_name}` when `name` is not a
  non-empty string of lowercase alphanumeric characters, hyphens, and dots.
  """
  @spec create_bucket(GenServer.server(), bucket()) ::
          :ok | {:error, :already_exists | :invalid_name}
  def create_bucket(server, name) do
    GenServer.call(server, {:create_bucket, name})
  end

  @doc """
  List all bucket names, sorted lexicographically.
  """
  @spec list_buckets(GenServer.server()) :: {:ok, [bucket()]}
  def list_buckets(server) do
    GenServer.call(server, :list_buckets)
  end

  @doc """
  Store an object under `bucket`/`key`.

  `data` must be a binary. `opts` may contain **at most one** precondition:

    * `{:if_none_match, "*"}` — succeed only if the key does not exist.
    * `{:if_match, etag}` — succeed only if the key exists and its ETag
      equals `etag`.

  With no precondition the write unconditionally creates or overwrites.

  Returns `{:ok, etag}` on success, `{:error, :precondition_failed}` when a
  precondition is not met (leaving any existing object unchanged), or
  `{:error, :bucket_not_found}` when the bucket does not exist.
  """
  @spec put_object(GenServer.server(), bucket(), key(), binary(), keyword()) ::
          {:ok, etag()} | {:error, :bucket_not_found | :precondition_failed}
  def put_object(server, bucket, key, data, opts \\ []) when is_binary(data) do
    GenServer.call(server, {:put_object, bucket, key, data, opts})
  end

  @doc """
  Retrieve an object stored under `bucket`/`key`.

  Returns `{:ok, %{data: binary, etag: string, size: integer,
  last_modified: DateTime.t()}}` on success.

  `opts` may contain `{:if_none_match, etag}`: if the object's current ETag
  equals `etag`, `{:error, :not_modified}` is returned instead of the body.

  Returns `{:error, :bucket_not_found}` or `{:error, :not_found}` on failure.
  """
  @spec get_object(GenServer.server(), bucket(), key(), keyword()) ::
          {:ok,
           %{data: binary(), etag: etag(), size: non_neg_integer(), last_modified: DateTime.t()}}
          | {:error, :bucket_not_found | :not_found | :not_modified}
  def get_object(server, bucket, key, opts \\ []) do
    GenServer.call(server, {:get_object, bucket, key, opts})
  end

  @doc """
  Delete the object stored under `bucket`/`key`.

  With no precondition this is an idempotent delete returning `:ok` even if
  the key is absent. `opts` may contain `{:if_match, etag}`, in which case
  the delete succeeds only if the key exists and its ETag matches;
  otherwise `{:error, :precondition_failed}` is returned and the object is
  left in place.

  Returns `{:error, :bucket_not_found}` if the bucket does not exist.
  """
  @spec delete_object(GenServer.server(), bucket(), key(), keyword()) ::
          :ok | {:error, :bucket_not_found | :precondition_failed}
  def delete_object(server, bucket, key, opts \\ []) do
    GenServer.call(server, {:delete_object, bucket, key, opts})
  end

  @doc """
  List the objects in `bucket`, sorted lexicographically by key.

  Each entry is `%{key: string, etag: string, size: integer,
  last_modified: DateTime.t()}`. Returns `{:error, :bucket_not_found}` when
  the bucket does not exist.
  """
  @spec list_objects(GenServer.server(), bucket()) ::
          {:ok,
           [%{key: key(), etag: etag(), size: non_neg_integer(), last_modified: DateTime.t()}]}
          | {:error, :bucket_not_found}
  def list_objects(server, bucket) do
    GenServer.call(server, {:list_objects, bucket})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  @spec init(term()) :: {:ok, state()}
  def init(_opts) do
    {:ok, %{buckets: %{}}}
  end

  @impl true
  def handle_call({:create_bucket, name}, _from, state) do
    cond do
      not valid_bucket_name?(name) ->
        {:reply, {:error, :invalid_name}, state}

      Map.has_key?(state.buckets, name) ->
        {:reply, {:error, :already_exists}, state}

      true ->
        new_state = put_in(state.buckets[name], %{})
        {:reply, :ok, new_state}
    end
  end

  def handle_call(:list_buckets, _from, state) do
    names = state.buckets |> Map.keys() |> Enum.sort()
    {:reply, {:ok, names}, state}
  end

  def handle_call({:put_object, bucket, key, data, opts}, _from, state) do
    case Map.fetch(state.buckets, bucket) do
      :error ->
        {:reply, {:error, :bucket_not_found}, state}

      {:ok, objects} ->
        do_put_object(state, bucket, objects, key, data, opts)
    end
  end

  def handle_call({:get_object, bucket, key, opts}, _from, state) do
    with {:ok, objects} <- fetch_bucket(state, bucket),
         {:ok, object} <- fetch_object(objects, key) do
      if Keyword.get(opts, :if_none_match) == object.etag do
        {:reply, {:error, :not_modified}, state}
      else
        view = Map.take(object, [:data, :etag, :size, :last_modified])
        {:reply, {:ok, view}, state}
      end
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:delete_object, bucket, key, opts}, _from, state) do
    case Map.fetch(state.buckets, bucket) do
      :error ->
        {:reply, {:error, :bucket_not_found}, state}

      {:ok, objects} ->
        do_delete_object(state, bucket, objects, key, opts)
    end
  end

  def handle_call({:list_objects, bucket}, _from, state) do
    case Map.fetch(state.buckets, bucket) do
      :error ->
        {:reply, {:error, :bucket_not_found}, state}

      {:ok, objects} ->
        entries =
          objects
          |> Enum.map(fn {key, object} ->
            object
            |> Map.take([:etag, :size, :last_modified])
            |> Map.put(:key, key)
          end)
          |> Enum.sort_by(& &1.key)

        {:reply, {:ok, entries}, state}
    end
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  @spec do_put_object(
          state(),
          bucket(),
          %{optional(key()) => object()},
          key(),
          binary(),
          keyword()
        ) :: {:reply, {:ok, etag()} | {:error, :precondition_failed}, state()}
  defp do_put_object(state, bucket, objects, key, data, opts) do
    if put_precondition_met?(objects, key, opts) do
      object = build_object(data)
      new_objects = Map.put(objects, key, object)
      new_state = put_in(state.buckets[bucket], new_objects)
      {:reply, {:ok, object.etag}, new_state}
    else
      {:reply, {:error, :precondition_failed}, state}
    end
  end

  @spec do_delete_object(state(), bucket(), %{optional(key()) => object()}, key(), keyword()) ::
          {:reply, :ok | {:error, :precondition_failed}, state()}
  defp do_delete_object(state, bucket, objects, key, opts) do
    case Keyword.fetch(opts, :if_match) do
      :error ->
        new_objects = Map.delete(objects, key)
        new_state = put_in(state.buckets[bucket], new_objects)
        {:reply, :ok, new_state}

      {:ok, expected} ->
        case Map.fetch(objects, key) do
          {:ok, %{etag: ^expected}} ->
            new_objects = Map.delete(objects, key)
            new_state = put_in(state.buckets[bucket], new_objects)
            {:reply, :ok, new_state}

          _other ->
            {:reply, {:error, :precondition_failed}, state}
        end
    end
  end

  @spec put_precondition_met?(%{optional(key()) => object()}, key(), keyword()) :: boolean()
  defp put_precondition_met?(objects, key, opts) do
    cond do
      Keyword.get(opts, :if_none_match) == "*" ->
        not Map.has_key?(objects, key)

      Keyword.has_key?(opts, :if_match) ->
        expected = Keyword.get(opts, :if_match)

        case Map.fetch(objects, key) do
          {:ok, %{etag: ^expected}} -> true
          _other -> false
        end

      true ->
        true
    end
  end

  @spec build_object(binary()) :: object()
  defp build_object(data) do
    %{
      data: data,
      etag: etag(data),
      size: byte_size(data),
      last_modified: DateTime.utc_now()
    }
  end

  @spec etag(binary()) :: etag()
  defp etag(data) do
    :sha256
    |> :crypto.hash(data)
    |> Base.encode16(case: :lower)
  end

  @spec fetch_bucket(state(), bucket()) ::
          {:ok, %{optional(key()) => object()}} | {:error, :bucket_not_found}
  defp fetch_bucket(state, bucket) do
    case Map.fetch(state.buckets, bucket) do
      {:ok, objects} -> {:ok, objects}
      :error -> {:error, :bucket_not_found}
    end
  end

  @spec fetch_object(%{optional(key()) => object()}, key()) ::
          {:ok, object()} | {:error, :not_found}
  defp fetch_object(objects, key) do
    case Map.fetch(objects, key) do
      {:ok, object} -> {:ok, object}
      :error -> {:error, :not_found}
    end
  end

  @spec valid_bucket_name?(term()) :: boolean()
  defp valid_bucket_name?(name) when is_binary(name) and name != "" do
    Regex.match?(@name_regex, name)
  end

  defp valid_bucket_name?(_name), do: false
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule ConditionalObjectStorageTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = ConditionalObjectStorage.start_link([])
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    %{os: pid}
  end

  defp etag_of(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)

  # -------------------------------------------------------
  # Buckets
  # -------------------------------------------------------

  test "create, list, invalid and duplicate buckets", %{os: os} do
    assert :ok = ConditionalObjectStorage.create_bucket(os, "beta")
    assert :ok = ConditionalObjectStorage.create_bucket(os, "alpha")
    assert {:ok, ["alpha", "beta"]} = ConditionalObjectStorage.list_buckets(os)
    assert {:error, :invalid_name} = ConditionalObjectStorage.create_bucket(os, "UP")
    assert {:error, :already_exists} = ConditionalObjectStorage.create_bucket(os, "alpha")
  end

  # -------------------------------------------------------
  # ETag semantics
  # -------------------------------------------------------

  test "put returns the sha256 hex etag of the data", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")
    assert {:ok, etag} = ConditionalObjectStorage.put_object(os, "b", "k", "hello world")
    assert etag == etag_of("hello world")
  end

  test "get returns data, etag, size and last_modified", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")
    ConditionalObjectStorage.put_object(os, "b", "k", "payload")

    assert {:ok, obj} = ConditionalObjectStorage.get_object(os, "b", "k")
    assert obj.data == "payload"
    assert obj.etag == etag_of("payload")
    assert obj.size == byte_size("payload")
    assert %DateTime{} = obj.last_modified
  end

  test "identical data yields identical etag; different data differs", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")
    {:ok, e1} = ConditionalObjectStorage.put_object(os, "b", "k", "same")
    {:ok, e2} = ConditionalObjectStorage.put_object(os, "b", "k", "same")
    {:ok, e3} = ConditionalObjectStorage.put_object(os, "b", "k", "different")
    assert e1 == e2
    assert e1 != e3
  end

  # -------------------------------------------------------
  # if_none_match: "*" (create-only)
  # -------------------------------------------------------

  test "if_none_match * creates only when absent", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")

    assert {:ok, _} =
             ConditionalObjectStorage.put_object(os, "b", "k", "first", if_none_match: "*")

    assert {:error, :precondition_failed} =
             ConditionalObjectStorage.put_object(os, "b", "k", "second", if_none_match: "*")

    # unchanged
    assert {:ok, %{data: "first"}} = ConditionalObjectStorage.get_object(os, "b", "k")
  end

  # -------------------------------------------------------
  # if_match: compare-and-swap
  # -------------------------------------------------------

  test "if_match succeeds on a matching etag and returns the new etag", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")
    {:ok, e1} = ConditionalObjectStorage.put_object(os, "b", "k", "v1")

    assert {:ok, e2} = ConditionalObjectStorage.put_object(os, "b", "k", "v2", if_match: e1)
    assert e2 == etag_of("v2")
    assert {:ok, %{data: "v2"}} = ConditionalObjectStorage.get_object(os, "b", "k")
  end

  test "if_match fails on a stale etag and leaves the object unchanged", %{os: os} do
    # TODO
  end

  test "if_match on a missing key fails the precondition", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")

    assert {:error, :precondition_failed} =
             ConditionalObjectStorage.put_object(os, "b", "k", "v", if_match: "anything")

    assert {:error, :not_found} = ConditionalObjectStorage.get_object(os, "b", "k")
  end

  test "put to a missing bucket returns bucket_not_found", %{os: os} do
    assert {:error, :bucket_not_found} = ConditionalObjectStorage.put_object(os, "nope", "k", "v")
  end

  # -------------------------------------------------------
  # Conditional get (cache revalidation)
  # -------------------------------------------------------

  test "get with if_none_match matching returns not_modified", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")
    {:ok, etag} = ConditionalObjectStorage.put_object(os, "b", "k", "body")

    assert {:error, :not_modified} =
             ConditionalObjectStorage.get_object(os, "b", "k", if_none_match: etag)

    assert {:ok, %{data: "body"}} =
             ConditionalObjectStorage.get_object(os, "b", "k", if_none_match: "other")
  end

  test "get errors for missing bucket and missing key", %{os: os} do
    assert {:error, :bucket_not_found} = ConditionalObjectStorage.get_object(os, "nope", "k")
    ConditionalObjectStorage.create_bucket(os, "b")
    assert {:error, :not_found} = ConditionalObjectStorage.get_object(os, "b", "missing")
  end

  # -------------------------------------------------------
  # Conditional / idempotent delete
  # -------------------------------------------------------

  test "delete is idempotent and reports bucket_not_found", %{os: os} do
    assert {:error, :bucket_not_found} = ConditionalObjectStorage.delete_object(os, "nope", "k")
    ConditionalObjectStorage.create_bucket(os, "b")
    assert :ok = ConditionalObjectStorage.delete_object(os, "b", "never")
  end

  test "delete with no precondition removes the existing object", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")
    {:ok, _} = ConditionalObjectStorage.put_object(os, "b", "gone", "v")
    {:ok, _} = ConditionalObjectStorage.put_object(os, "b", "kept", "w")

    assert :ok = ConditionalObjectStorage.delete_object(os, "b", "gone")
    assert {:error, :not_found} = ConditionalObjectStorage.get_object(os, "b", "gone")

    assert {:ok, remaining} = ConditionalObjectStorage.list_objects(os, "b")
    assert Enum.map(remaining, & &1.key) == ["kept"]

    # deleting the now-absent key again is still a success
    assert :ok = ConditionalObjectStorage.delete_object(os, "b", "gone")
    assert {:ok, %{data: "w"}} = ConditionalObjectStorage.get_object(os, "b", "kept")
  end

  test "delete with if_match succeeds only on a matching etag", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")
    {:ok, etag} = ConditionalObjectStorage.put_object(os, "b", "k", "v")

    assert {:error, :precondition_failed} =
             ConditionalObjectStorage.delete_object(os, "b", "k", if_match: "wrong")

    # object still there
    assert {:ok, %{data: "v"}} = ConditionalObjectStorage.get_object(os, "b", "k")

    assert :ok = ConditionalObjectStorage.delete_object(os, "b", "k", if_match: etag)
    assert {:error, :not_found} = ConditionalObjectStorage.get_object(os, "b", "k")
  end

  test "delete with if_match on a missing key fails the precondition", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")

    assert {:error, :precondition_failed} =
             ConditionalObjectStorage.delete_object(os, "b", "missing", if_match: "x")
  end

  test "a deleted key can be recreated with if_none_match *", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")
    {:ok, _} = ConditionalObjectStorage.put_object(os, "b", "k", "old")

    assert {:error, :precondition_failed} =
             ConditionalObjectStorage.put_object(os, "b", "k", "new", if_none_match: "*")

    assert :ok = ConditionalObjectStorage.delete_object(os, "b", "k")

    assert {:ok, etag} =
             ConditionalObjectStorage.put_object(os, "b", "k", "new", if_none_match: "*")

    assert etag == etag_of("new")
    assert {:ok, %{data: "new"}} = ConditionalObjectStorage.get_object(os, "b", "k")
  end

  # -------------------------------------------------------
  # Listing
  # -------------------------------------------------------

  test "list_objects returns sorted entries with etag and size", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")
    ConditionalObjectStorage.put_object(os, "b", "c", "333")
    ConditionalObjectStorage.put_object(os, "b", "a", "1")
    ConditionalObjectStorage.put_object(os, "b", "b", "22")

    assert {:ok, objs} = ConditionalObjectStorage.list_objects(os, "b")
    assert Enum.map(objs, & &1.key) == ["a", "b", "c"]
    a = Enum.find(objs, &(&1.key == "a"))
    assert a.size == 1
    assert a.etag == etag_of("1")
    assert %DateTime{} = a.last_modified
  end

  test "list_objects on a missing bucket errors", %{os: os} do
    assert {:error, :bucket_not_found} = ConditionalObjectStorage.list_objects(os, "nope")
  end

  test "put with a precondition on a missing bucket reports bucket_not_found not precondition", %{
    os: os
  } do
    assert {:error, :bucket_not_found} =
             ConditionalObjectStorage.put_object(os, "nope", "k", "v", if_none_match: "*")

    assert {:error, :bucket_not_found} =
             ConditionalObjectStorage.put_object(os, "nope", "k", "v", if_match: "anything")
  end

  test "delete with if_match on a missing bucket reports bucket_not_found", %{os: os} do
    assert {:error, :bucket_not_found} =
             ConditionalObjectStorage.delete_object(os, "nope", "k", if_match: "some-etag")
  end

  test "start_link registers the process under the given name option" do
    name = :cos_named_registration_test
    {:ok, pid} = ConditionalObjectStorage.start_link(name: name)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    assert Process.whereis(name) == pid
    assert :ok = ConditionalObjectStorage.create_bucket(name, "b")
    assert {:ok, ["b"]} = ConditionalObjectStorage.list_buckets(name)
  end

  test "an empty bucket name is rejected as invalid_name", %{os: os} do
    assert {:error, :invalid_name} = ConditionalObjectStorage.create_bucket(os, "")
    assert {:ok, []} = ConditionalObjectStorage.list_buckets(os)
  end

  test "bucket names with hyphens, dots and digits are accepted", %{os: os} do
    assert :ok = ConditionalObjectStorage.create_bucket(os, "my-bucket.v2")
    assert :ok = ConditionalObjectStorage.create_bucket(os, "a.b-c9")
    assert {:ok, ["a.b-c9", "my-bucket.v2"]} = ConditionalObjectStorage.list_buckets(os)
    assert {:error, :invalid_name} = ConditionalObjectStorage.create_bucket(os, "has_underscore")
  end

  test "delete with a stale etag from a previous version leaves the object in place", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")
    {:ok, old_etag} = ConditionalObjectStorage.put_object(os, "b", "k", "v1")
    {:ok, new_etag} = ConditionalObjectStorage.put_object(os, "b", "k", "v2")

    assert {:error, :precondition_failed} =
             ConditionalObjectStorage.delete_object(os, "b", "k", if_match: old_etag)

    assert {:ok, %{data: "v2"}} = ConditionalObjectStorage.get_object(os, "b", "k")
    assert :ok = ConditionalObjectStorage.delete_object(os, "b", "k", if_match: new_etag)
    assert {:error, :not_found} = ConditionalObjectStorage.get_object(os, "b", "k")
  end
end
```
