# Implement the missing function

Below you'll find a task's full specification, then a working, tested
solution with one gap: `get_object` — every clause body swapped for
`# TODO`. Rebuild exactly that function so the module passes the task's
whole suite again, and leave every other line precisely as shown.

## The task

# Conditional-Write Object Store with ETags

Write me an Elixir GenServer module called `ConditionalObjectStorage` — an S3-like, **in-memory** object store that supports **optimistic concurrency** through conditional requests, exactly like S3's `If-Match` / `If-None-Match` preconditions. Every stored object carries an **ETag**, defined as the **lowercase hex-encoded SHA-256 of the object's data** (so identical data always yields the same ETag, and different data yields a different ETag).

## Public API

- `ConditionalObjectStorage.start_link(opts)` — start the process. Accepts a `:name` option for registration.

- `ConditionalObjectStorage.create_bucket(server, name)` — create a bucket. Return `:ok`, or `{:error, :already_exists}`. Bucket names must be non-empty strings of lowercase alphanumeric characters, hyphens, and dots — otherwise `{:error, :invalid_name}`.

- `ConditionalObjectStorage.list_buckets(server)` — return `{:ok, [bucket_name]}`, sorted.

- `ConditionalObjectStorage.put_object(server, bucket, key, data, opts \\ [])` — store an object. `data` is a binary. `opts` may contain **at most one** precondition:
  - `:if_none_match` with the value `"*"` — the write succeeds only if the key does **not** currently exist (a create-only / no-overwrite write). If the key already exists, return `{:error, :precondition_failed}` and leave the stored object unchanged.
  - `:if_match` with an ETag string — the write succeeds only if the key currently exists **and** its ETag equals the given value (a compare-and-swap). If the key is absent or its ETag differs, return `{:error, :precondition_failed}` and leave any stored object unchanged.
  - With no precondition, the write unconditionally creates or overwrites.

  On success, return `{:ok, etag}` where `etag` is the new object's ETag. Return `{:error, :bucket_not_found}` if the bucket does not exist (preconditions are only evaluated for an existing bucket).

- `ConditionalObjectStorage.get_object(server, bucket, key, opts \\ [])` — retrieve an object. Return `{:ok, %{data: binary, etag: string, size: integer, last_modified: DateTime.t()}}`. `opts` may contain `:if_none_match` with an ETag string: if the object's current ETag equals that value, return `{:error, :not_modified}` instead of the body (a cache-revalidation read). Return `{:error, :bucket_not_found}` or `{:error, :not_found}` on failure.

- `ConditionalObjectStorage.delete_object(server, bucket, key, opts \\ [])` — remove an object. With no precondition this is an idempotent delete: return `:ok` even if the key does not exist. `opts` may contain `:if_match` with an ETag string — the delete then succeeds only if the key exists and its ETag matches; otherwise return `{:error, :precondition_failed}` and leave the object in place. Return `{:error, :bucket_not_found}` if the bucket is missing.

- `ConditionalObjectStorage.list_objects(server, bucket)` — return `{:ok, [%{key: string, etag: string, size: integer, last_modified: DateTime.t()}]}` sorted lexicographically by key, or `{:error, :bucket_not_found}`.

Storage is in memory only and does not need to survive a restart. Give me the complete module in a single file. Use only the OTP standard library — no external dependencies.

## The module with `get_object` missing

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

  def get_object(server, bucket, key, opts \\ []) do
    # TODO
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

Reply with `get_object` alone (bring along any `@doc`/`@spec`/`@impl` lines
that belong directly above it) — just the function, never the whole
module.
