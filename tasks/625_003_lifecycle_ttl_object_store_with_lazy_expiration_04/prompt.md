# Lifecycle TTL Object Store with Lazy Expiration — implement the `{:get_object, bucket, key}` clause of `handle_call/3`

Below is a complete `TtlObjectStorage` module — an S3-like, in-memory object store
with lifecycle TTL expiration — with the body of one function removed.

Implement the `handle_call/3` clause that handles the `{:get_object, bucket, key}`
message. It should look the bucket up in `state.buckets`. If the bucket does not
exist, reply `{:error, :bucket_not_found}` and leave the state unchanged. If the
bucket exists, look the key up in that bucket's object map:

  * If the key is absent, reply `{:error, :not_found}` with the state unchanged.
  * If the key is present but the object has expired (use the `expired?/2` helper
    against the current monotonic time from `now_ms/0`), apply lazy expiration:
    delete the object from the bucket, reply `{:error, :not_found}`, and return the
    updated state (use the `put_bucket/3` helper to write the bucket back).
  * If the key is present and the object is live, reply
    `{:ok, %{data: binary, size: integer, last_modified: DateTime.t()}}` — that is,
    the object map with only the `:data`, `:size`, and `:last_modified` fields, with
    the internal `:expires_at` deadline stripped out — leaving the state unchanged.

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
    # TODO
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