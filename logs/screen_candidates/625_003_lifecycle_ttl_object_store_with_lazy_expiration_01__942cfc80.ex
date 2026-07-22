defmodule TtlObjectStorage do
  @moduledoc """
  An S3-like, in-memory object store with lifecycle (TTL) expiration.

  Objects are grouped into buckets and may carry a time-to-live expressed in milliseconds,
  measured from the moment of the `put_object/5` (or `set_ttl/4`) call. A TTL of `:infinity`
  means the object never expires.

  Expiration is **lazy**: an expired object is treated as absent by every read/write path and
  is removed the moment it is next touched. `purge_expired/1` additionally sweeps every bucket
  and reclaims all currently-expired objects in bulk.

  All state lives in the process heap; nothing is persisted, so the contents of the store do
  not survive a restart.

  ## Example

      {:ok, pid} = TtlObjectStorage.start_link(default_ttl_ms: 60_000)
      :ok = TtlObjectStorage.create_bucket(pid, "my-bucket")
      :ok = TtlObjectStorage.put_object(pid, "my-bucket", "a.txt", "hello", ttl_ms: 50)
      {:ok, %{data: "hello"}} = TtlObjectStorage.get_object(pid, "my-bucket", "a.txt")
      Process.sleep(60)
      {:error, :not_found} = TtlObjectStorage.get_object(pid, "my-bucket", "a.txt")

  """

  use GenServer

  @typedoc "A time-to-live in milliseconds, or `:infinity` for an object that never expires."
  @type ttl :: pos_integer() | :infinity

  @typedoc "Anything accepted as a GenServer destination (pid, registered name, `{:via, _, _}`)."
  @type server :: GenServer.server()

  @typedoc "Metadata describing a live object, as returned by `list_objects/2`."
  @type object_info :: %{key: String.t(), size: non_neg_integer(), last_modified: DateTime.t()}

  @typedoc "A live object together with its payload, as returned by `get_object/3`."
  @type object :: %{data: binary(), size: non_neg_integer(), last_modified: DateTime.t()}

  @bucket_name_regex ~r/^[a-z0-9.\-]+$/

  # Internal object representation. `expires_at` is a monotonic timestamp in milliseconds
  # (or `:infinity`), which makes expiry immune to wall-clock adjustments.
  defmodule Object do
    @moduledoc false
    @enforce_keys [:data, :size, :last_modified, :expires_at]
    defstruct [:data, :size, :last_modified, :expires_at]
  end

  ## ------------------------------------------------------------------
  ## Public API
  ## ------------------------------------------------------------------

  @doc """
  Starts the object store.

  ## Options

    * `:name` — an optional name under which to register the process.
    * `:default_ttl_ms` — the TTL applied to `put_object/5` calls that do not supply their own
      `:ttl_ms`. Must be a positive integer number of milliseconds or `:infinity`
      (the default).

  Any other option is ignored. Raises `ArgumentError` if `:default_ttl_ms` is invalid.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    default_ttl = Keyword.get(opts, :default_ttl_ms, :infinity)

    unless valid_ttl?(default_ttl) do
      raise ArgumentError,
            ":default_ttl_ms must be a positive integer or :infinity, got: " <>
              inspect(default_ttl)
    end

    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, %{default_ttl_ms: default_ttl}, server_opts)
  end

  @doc """
  Creates a bucket named `name`.

  Bucket names must be non-empty strings made up of lowercase alphanumeric characters,
  hyphens and dots.

  Returns `:ok`, `{:error, :invalid_name}` or `{:error, :already_exists}`.
  """
  @spec create_bucket(server(), String.t()) ::
          :ok | {:error, :invalid_name | :already_exists}
  def create_bucket(server, name) do
    GenServer.call(server, {:create_bucket, name})
  end

  @doc """
  Returns `{:ok, names}` with every bucket name currently known to the store, sorted.
  """
  @spec list_buckets(server()) :: {:ok, [String.t()]}
  def list_buckets(server) do
    GenServer.call(server, :list_buckets)
  end

  @doc """
  Deletes the bucket `name`.

  The bucket is deleted only when it holds no live objects; objects that have already expired
  are ignored (and reclaimed) and therefore never block the deletion.

  Returns `:ok`, `{:error, :not_found}` or `{:error, :not_empty}`.
  """
  @spec delete_bucket(server(), String.t()) :: :ok | {:error, :not_found | :not_empty}
  def delete_bucket(server, name) do
    GenServer.call(server, {:delete_bucket, name})
  end

  @doc """
  Stores `data` under `key` in `bucket`, overwriting (and re-arming the TTL of) any object
  already stored under that key.

  ## Options

    * `:ttl_ms` — a positive integer number of milliseconds, or `:infinity`. Defaults to the
      server's `:default_ttl_ms`.

  Returns `:ok` or `{:error, :bucket_not_found}`. Raises `ArgumentError` on an invalid TTL.
  """
  @spec put_object(server(), String.t(), String.t(), binary(), keyword()) ::
          :ok | {:error, :bucket_not_found}
  def put_object(server, bucket, key, data, opts \\ [])
      when is_binary(data) and is_list(opts) do
    ttl = Keyword.get(opts, :ttl_ms, :default)

    unless ttl == :default or valid_ttl?(ttl) do
      raise ArgumentError, ":ttl_ms must be a positive integer or :infinity, got: #{inspect(ttl)}"
    end

    GenServer.call(server, {:put_object, bucket, key, data, ttl})
  end

  @doc """
  Fetches the live object stored under `key` in `bucket`.

  Returns `{:ok, %{data: binary, size: integer, last_modified: DateTime.t()}}`.

  Returns `{:error, :bucket_not_found}` when the bucket does not exist and `{:error, :not_found}`
  when the key is absent or has expired. An expired object encountered here is removed (lazy
  expiration).
  """
  @spec get_object(server(), String.t(), String.t()) ::
          {:ok, object()} | {:error, :bucket_not_found | :not_found}
  def get_object(server, bucket, key) do
    GenServer.call(server, {:get_object, bucket, key})
  end

  @doc """
  Removes the object stored under `key` in `bucket`.

  The operation is idempotent: it returns `:ok` even when the key does not exist (or had
  already expired). Returns `{:error, :bucket_not_found}` when the bucket is missing.
  """
  @spec delete_object(server(), String.t(), String.t()) :: :ok | {:error, :bucket_not_found}
  def delete_object(server, bucket, key) do
    GenServer.call(server, {:delete_object, bucket, key})
  end

  @doc """
  Lists the live objects of `bucket`, sorted lexicographically by key.

  Expired objects are excluded from the listing (and reclaimed). Returns
  `{:ok, [%{key: string, size: integer, last_modified: DateTime.t()}]}` or
  `{:error, :bucket_not_found}`.
  """
  @spec list_objects(server(), String.t()) ::
          {:ok, [object_info()]} | {:error, :bucket_not_found}
  def list_objects(server, bucket) do
    GenServer.call(server, {:list_objects, bucket})
  end

  @doc """
  Re-arms the TTL of the live object stored under `key` in `bucket`, measured from now.

  `ttl_ms` is a positive integer or `:infinity`. Returns `:ok`, `{:error, :bucket_not_found}`,
  or `{:error, :not_found}` when the key is absent or has already expired. Raises
  `ArgumentError` on an invalid TTL.
  """
  @spec set_ttl(server(), String.t(), String.t(), ttl()) ::
          :ok | {:error, :bucket_not_found | :not_found}
  def set_ttl(server, bucket, key, ttl_ms) do
    unless valid_ttl?(ttl_ms) do
      raise ArgumentError,
            "ttl_ms must be a positive integer or :infinity, got: #{inspect(ttl_ms)}"
    end

    GenServer.call(server, {:set_ttl, bucket, key, ttl_ms})
  end

  @doc """
  Sweeps every bucket and permanently removes all currently-expired objects.

  Returns `{:ok, count}`, where `count` is the number of objects that were removed.
  """
  @spec purge_expired(server()) :: {:ok, non_neg_integer()}
  def purge_expired(server) do
    GenServer.call(server, :purge_expired)
  end

  ## ------------------------------------------------------------------
  ## GenServer callbacks
  ## ------------------------------------------------------------------

  @impl GenServer
  def init(%{default_ttl_ms: default_ttl}) do
    {:ok, %{buckets: %{}, default_ttl_ms: default_ttl}}
  end

  @impl GenServer
  def handle_call({:create_bucket, name}, _from, state) do
    cond do
      not valid_bucket_name?(name) ->
        {:reply, {:error, :invalid_name}, state}

      Map.has_key?(state.buckets, name) ->
        {:reply, {:error, :already_exists}, state}

      true ->
        {:reply, :ok, put_in(state.buckets[name], %{})}
    end
  end

  def handle_call(:list_buckets, _from, state) do
    {:reply, {:ok, state.buckets |> Map.keys() |> Enum.sort()}, state}
  end

  def handle_call({:delete_bucket, name}, _from, state) do
    case Map.fetch(state.buckets, name) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, objects} ->
        now = now_ms()

        if Enum.any?(objects, fn {_key, object} -> live?(object, now) end) do
          {:reply, {:error, :not_empty}, state}
        else
          {:reply, :ok, %{state | buckets: Map.delete(state.buckets, name)}}
        end
    end
  end

  def handle_call({:put_object, bucket, key, data, ttl}, _from, state) do
    with_bucket(state, bucket, fn objects ->
      ttl = if ttl == :default, do: state.default_ttl_ms, else: ttl
      {:ok, :ok, Map.put(objects, key, build_object(data, ttl, now_ms()))}
    end)
  end

  def handle_call({:get_object, bucket, key}, _from, state) do
    with_bucket(state, bucket, fn objects ->
      case fetch_live(objects, key, now_ms()) do
        {:ok, object} ->
          reply = %{data: object.data, size: object.size, last_modified: object.last_modified}
          {:ok, {:ok, reply}, objects}

        :expired ->
          {:ok, {:error, :not_found}, Map.delete(objects, key)}

        :error ->
          {:ok, {:error, :not_found}, objects}
      end
    end)
  end

  def handle_call({:delete_object, bucket, key}, _from, state) do
    with_bucket(state, bucket, fn objects ->
      {:ok, :ok, Map.delete(objects, key)}
    end)
  end

  def handle_call({:list_objects, bucket}, _from, state) do
    with_bucket(state, bucket, fn objects ->
      now = now_ms()
      live = Map.filter(objects, fn {_key, object} -> live?(object, now) end)

      listing =
        live
        |> Enum.map(fn {key, object} ->
          %{key: key, size: object.size, last_modified: object.last_modified}
        end)
        |> Enum.sort_by(& &1.key)

      {:ok, {:ok, listing}, live}
    end)
  end

  def handle_call({:set_ttl, bucket, key, ttl}, _from, state) do
    with_bucket(state, bucket, fn objects ->
      now = now_ms()

      case fetch_live(objects, key, now) do
        {:ok, object} ->
          object = %Object{object | expires_at: expires_at(ttl, now)}
          {:ok, :ok, Map.put(objects, key, object)}

        :expired ->
          {:ok, {:error, :not_found}, Map.delete(objects, key)}

        :error ->
          {:ok, {:error, :not_found}, objects}
      end
    end)
  end

  def handle_call(:purge_expired, _from, state) do
    now = now_ms()

    {buckets, removed} =
      Enum.reduce(state.buckets, {%{}, 0}, fn {name, objects}, {acc, count} ->
        live = Map.filter(objects, fn {_key, object} -> live?(object, now) end)
        {Map.put(acc, name, live), count + (map_size(objects) - map_size(live))}
      end)

    {:reply, {:ok, removed}, %{state | buckets: buckets}}
  end

  ## ------------------------------------------------------------------
  ## Internal helpers
  ## ------------------------------------------------------------------

  # Runs `fun` against the objects of `bucket`, threading the (possibly updated) object map
  # back into the state. Replies `{:error, :bucket_not_found}` when the bucket is missing.
  @spec with_bucket(map(), String.t(), (map() -> {:ok, term(), map()})) ::
          {:reply, term(), map()}
  defp with_bucket(state, bucket, fun) do
    case Map.fetch(state.buckets, bucket) do
      :error ->
        {:reply, {:error, :bucket_not_found}, state}

      {:ok, objects} ->
        {:ok, reply, new_objects} = fun.(objects)
        {:reply, reply, put_in(state.buckets[bucket], new_objects)}
    end
  end

  @spec fetch_live(map(), String.t(), integer()) :: {:ok, Object.t()} | :expired | :error
  defp fetch_live(objects, key, now) do
    case Map.fetch(objects, key) do
      {:ok, object} -> if live?(object, now), do: {:ok, object}, else: :expired
      :error -> :error
    end
  end

  @spec build_object(binary(), ttl(), integer()) :: Object.t()
  defp build_object(data, ttl, now) do
    %Object{
      data: data,
      size: byte_size(data),
      last_modified: DateTime.utc_now(),
      expires_at: expires_at(ttl, now)
    }
  end

  @spec expires_at(ttl(), integer()) :: integer() | :infinity
  defp expires_at(:infinity, _now), do: :infinity
  defp expires_at(ttl_ms, now) when is_integer(ttl_ms), do: now + ttl_ms

  @spec live?(Object.t(), integer()) :: boolean()
  defp live?(%Object{expires_at: :infinity}, _now), do: true
  defp live?(%Object{expires_at: expires_at}, now), do: now < expires_at

  @spec valid_ttl?(term()) :: boolean()
  defp valid_ttl?(:infinity), do: true
  defp valid_ttl?(ttl) when is_integer(ttl) and ttl > 0, do: true
  defp valid_ttl?(_ttl), do: false

  @spec valid_bucket_name?(term()) :: boolean()
  defp valid_bucket_name?(name) when is_binary(name) and byte_size(name) > 0 do
    Regex.match?(@bucket_name_regex, name)
  end

  defp valid_bucket_name?(_name), do: false

  @spec now_ms() :: integer()
  defp now_ms, do: System.monotonic_time(:millisecond)
end