defmodule ConditionalObjectStorage do
  @moduledoc """
  An S3-like, in-memory object store with support for optimistic concurrency via
  conditional requests.

  Objects are grouped into buckets. Every stored object carries an **ETag**, defined as the
  lowercase hex-encoded SHA-256 digest of the object's data. Because the ETag is a pure
  function of the bytes, identical data always yields the same ETag and different data
  yields a different ETag.

  Conditional requests mirror the HTTP/S3 preconditions:

    * `put_object/5` with `if_none_match: "*"` — create-only write (fails if the key exists).
    * `put_object/5` with `if_match: etag` — compare-and-swap (fails if absent or changed).
    * `get_object/4` with `if_none_match: etag` — cache revalidation (`{:error, :not_modified}`).
    * `delete_object/4` with `if_match: etag` — conditional delete.

  All state lives in the process heap; nothing is persisted, so contents do not survive a
  restart. Since every operation is serialized through this `GenServer`, read-modify-write
  sequences guarded by a precondition are atomic with respect to concurrent callers.

  ## Example

      {:ok, store} = ConditionalObjectStorage.start_link([])
      :ok = ConditionalObjectStorage.create_bucket(store, "my-bucket")
      {:ok, etag} = ConditionalObjectStorage.put_object(store, "my-bucket", "k", "v")

      # Compare-and-swap: only overwrite if nobody else changed it.
      {:ok, _new_etag} =
        ConditionalObjectStorage.put_object(store, "my-bucket", "k", "v2", if_match: etag)

      # The stale ETag no longer matches.
      {:error, :precondition_failed} =
        ConditionalObjectStorage.put_object(store, "my-bucket", "k", "v3", if_match: etag)
  """

  use GenServer

  @typedoc "A running `ConditionalObjectStorage` process."
  @type server :: GenServer.server()

  @typedoc "A bucket name."
  @type bucket :: String.t()

  @typedoc "An object key."
  @type key :: String.t()

  @typedoc "A lowercase hex-encoded SHA-256 digest of an object's data."
  @type etag :: String.t()

  @typedoc "Metadata describing a stored object, as returned by `list_objects/2`."
  @type object_meta :: %{
          key: key(),
          etag: etag(),
          size: non_neg_integer(),
          last_modified: DateTime.t()
        }

  @typedoc "A stored object plus its metadata, as returned by `get_object/4`."
  @type object :: %{
          data: binary(),
          etag: etag(),
          size: non_neg_integer(),
          last_modified: DateTime.t()
        }

  @typedoc "Preconditions accepted by `put_object/5`."
  @type put_opt :: {:if_match, etag()} | {:if_none_match, String.t()}

  @typedoc "Preconditions accepted by `get_object/4`."
  @type get_opt :: {:if_none_match, etag()}

  @typedoc "Preconditions accepted by `delete_object/4`."
  @type delete_opt :: {:if_match, etag()}

  # Internal state: a map of bucket name => (map of key => stored object).
  defmodule State do
    @moduledoc false
    defstruct buckets: %{}
  end

  @bucket_name_regex ~r/\A[a-z0-9.\-]+\z/

  ## Client API

  @doc """
  Starts the object store process.

  Accepts the usual `GenServer` options; in particular `:name` may be given to register the
  process (e.g. `start_link(name: MyStore)`).

  Returns `{:ok, pid}` on success.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Creates a bucket named `name`.

  Bucket names must be non-empty strings made up of lowercase alphanumeric characters,
  hyphens and dots.

  Returns `:ok`, `{:error, :already_exists}` if a bucket with that name is already present,
  or `{:error, :invalid_name}` if the name is not valid.
  """
  @spec create_bucket(server(), bucket()) :: :ok | {:error, :already_exists | :invalid_name}
  def create_bucket(server, name) do
    GenServer.call(server, {:create_bucket, name})
  end

  @doc """
  Lists the names of all buckets, sorted lexicographically.

  Returns `{:ok, names}`.
  """
  @spec list_buckets(server()) :: {:ok, [bucket()]}
  def list_buckets(server) do
    GenServer.call(server, :list_buckets)
  end

  @doc """
  Stores `data` under `key` in `bucket`, subject to an optional precondition.

  `opts` may carry **at most one** of:

    * `:if_none_match` — must be `"*"`. The write only succeeds if `key` does not currently
      exist (a create-only write).
    * `:if_match` — an ETag string. The write only succeeds if `key` exists and its current
      ETag equals the given value (a compare-and-swap).

  With no precondition the write unconditionally creates or overwrites the object.

  Returns `{:ok, etag}` with the new object's ETag on success. Returns
  `{:error, :precondition_failed}` (leaving any stored object untouched) when the
  precondition is not met, `{:error, :bucket_not_found}` if the bucket does not exist, or
  `{:error, :invalid_precondition}` if `opts` contains more than one precondition or an
  unsupported `:if_none_match` value.
  """
  @spec put_object(server(), bucket(), key(), binary(), [put_opt()]) ::
          {:ok, etag()}
          | {:error, :bucket_not_found | :precondition_failed | :invalid_precondition}
  def put_object(server, bucket, key, data, opts \\ []) when is_binary(data) do
    GenServer.call(server, {:put_object, bucket, key, data, opts})
  end

  @doc """
  Retrieves the object stored under `key` in `bucket`.

  `opts` may carry `:if_none_match` with an ETag string: if the object's current ETag equals
  that value, `{:error, :not_modified}` is returned instead of the body, which lets a caller
  cheaply revalidate a cached copy.

  Returns `{:ok, %{data: binary, etag: string, size: integer, last_modified: DateTime.t()}}`
  on success, or `{:error, :bucket_not_found}`, `{:error, :not_found}` or
  `{:error, :not_modified}`.
  """
  @spec get_object(server(), bucket(), key(), [get_opt()]) ::
          {:ok, object()}
          | {:error, :bucket_not_found | :not_found | :not_modified | :invalid_precondition}
  def get_object(server, bucket, key, opts \\ []) do
    GenServer.call(server, {:get_object, bucket, key, opts})
  end

  @doc """
  Deletes the object stored under `key` in `bucket`.

  With no precondition the delete is idempotent: `:ok` is returned even when `key` is absent.

  `opts` may carry `:if_match` with an ETag string, in which case the delete only succeeds if
  the object exists and its current ETag matches; otherwise `{:error, :precondition_failed}`
  is returned and the object is left in place.

  Returns `:ok`, `{:error, :bucket_not_found}` or `{:error, :precondition_failed}`.
  """
  @spec delete_object(server(), bucket(), key(), [delete_opt()]) ::
          :ok | {:error, :bucket_not_found | :precondition_failed | :invalid_precondition}
  def delete_object(server, bucket, key, opts \\ []) do
    GenServer.call(server, {:delete_object, bucket, key, opts})
  end

  @doc """
  Lists metadata for every object in `bucket`, sorted lexicographically by key.

  Returns `{:ok, objects}` where each entry is a map with `:key`, `:etag`, `:size` and
  `:last_modified`, or `{:error, :bucket_not_found}`.
  """
  @spec list_objects(server(), bucket()) :: {:ok, [object_meta()]} | {:error, :bucket_not_found}
  def list_objects(server, bucket) do
    GenServer.call(server, {:list_objects, bucket})
  end

  @doc """
  Computes the ETag for `data`: the lowercase hex-encoded SHA-256 digest of the bytes.

  Exposed so callers can predict the ETag a write will produce without contacting the store.
  """
  @spec etag(binary()) :: etag()
  def etag(data) when is_binary(data) do
    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
  end

  ## Server callbacks

  @impl GenServer
  def init(_opts) do
    {:ok, %State{}}
  end

  @impl GenServer
  def handle_call({:create_bucket, name}, _from, state) do
    cond do
      not valid_bucket_name?(name) ->
        {:reply, {:error, :invalid_name}, state}

      Map.has_key?(state.buckets, name) ->
        {:reply, {:error, :already_exists}, state}

      true ->
        {:reply, :ok, %State{state | buckets: Map.put(state.buckets, name, %{})}}
    end
  end

  def handle_call(:list_buckets, _from, state) do
    {:reply, {:ok, state.buckets |> Map.keys() |> Enum.sort()}, state}
  end

  def handle_call({:put_object, bucket, key, data, opts}, _from, state) do
    with {:ok, objects} <- fetch_bucket(state, bucket),
         {:ok, precondition} <- parse_precondition(opts, [:if_match, :if_none_match]),
         :ok <- check_put_precondition(precondition, Map.get(objects, key)) do
      object = new_object(data)
      objects = Map.put(objects, key, object)
      {:reply, {:ok, object.etag}, put_bucket(state, bucket, objects)}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:get_object, bucket, key, opts}, _from, state) do
    with {:ok, objects} <- fetch_bucket(state, bucket),
         {:ok, precondition} <- parse_precondition(opts, [:if_none_match]),
         {:ok, object} <- fetch_object(objects, key),
         :ok <- check_get_precondition(precondition, object) do
      {:reply, {:ok, object}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:delete_object, bucket, key, opts}, _from, state) do
    with {:ok, objects} <- fetch_bucket(state, bucket),
         {:ok, precondition} <- parse_precondition(opts, [:if_match]),
         :ok <- check_delete_precondition(precondition, Map.get(objects, key)) do
      objects = Map.delete(objects, key)
      {:reply, :ok, put_bucket(state, bucket, objects)}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:list_objects, bucket}, _from, state) do
    case fetch_bucket(state, bucket) do
      {:ok, objects} ->
        listing =
          objects
          |> Enum.map(fn {key, object} ->
            %{
              key: key,
              etag: object.etag,
              size: object.size,
              last_modified: object.last_modified
            }
          end)
          |> Enum.sort_by(& &1.key)

        {:reply, {:ok, listing}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  ## Internal helpers

  @spec valid_bucket_name?(term()) :: boolean()
  defp valid_bucket_name?(name) when is_binary(name) and name != "" do
    Regex.match?(@bucket_name_regex, name)
  end

  defp valid_bucket_name?(_name), do: false

  @spec fetch_bucket(State.t(), term()) :: {:ok, map()} | {:error, :bucket_not_found}
  defp fetch_bucket(state, bucket) do
    case Map.fetch(state.buckets, bucket) do
      {:ok, objects} -> {:ok, objects}
      :error -> {:error, :bucket_not_found}
    end
  end

  @spec put_bucket(State.t(), bucket(), map()) :: State.t()
  defp put_bucket(state, bucket, objects) do
    %State{state | buckets: Map.put(state.buckets, bucket, objects)}
  end

  @spec fetch_object(map(), term()) :: {:ok, object()} | {:error, :not_found}
  defp fetch_object(objects, key) do
    case Map.fetch(objects, key) do
      {:ok, object} -> {:ok, object}
      :error -> {:error, :not_found}
    end
  end

  @spec new_object(binary()) :: object()
  defp new_object(data) do
    %{
      data: data,
      etag: etag(data),
      size: byte_size(data),
      last_modified: DateTime.utc_now()
    }
  end

  # Extracts at most one precondition from `opts`, restricted to `allowed` keys. Any other
  # option key is ignored; supplying more than one precondition is an error.
  @spec parse_precondition(keyword(), [atom()]) ::
          {:ok, nil | {atom(), String.t()}} | {:error, :invalid_precondition}
  defp parse_precondition(opts, allowed) when is_list(opts) do
    case Enum.filter(opts, fn {k, _v} -> k in allowed end) do
      [] ->
        {:ok, nil}

      [{:if_none_match, "*"} = precondition] ->
        {:ok, precondition}

      [{:if_none_match, value} = precondition] when is_binary(value) ->
        # A concrete ETag is only meaningful for reads; `put_object/5` rejects it below.
        if :if_match in allowed, do: {:error, :invalid_precondition}, else: {:ok, precondition}

      [{:if_match, value} = precondition] when is_binary(value) ->
        {:ok, precondition}

      _other ->
        {:error, :invalid_precondition}
    end
  end

  # `if_none_match: "*"` — succeed only when nothing is stored under the key.
  @spec check_put_precondition(nil | {atom(), String.t()}, nil | object()) ::
          :ok | {:error, :precondition_failed}
  defp check_put_precondition(nil, _current), do: :ok
  defp check_put_precondition({:if_none_match, "*"}, nil), do: :ok
  defp check_put_precondition({:if_none_match, "*"}, _current), do: {:error, :precondition_failed}
  defp check_put_precondition({:if_match, _etag}, nil), do: {:error, :precondition_failed}

  defp check_put_precondition({:if_match, etag}, %{etag: etag}), do: :ok
  defp check_put_precondition({:if_match, _etag}, _current), do: {:error, :precondition_failed}

  # `if_none_match: etag` — the caller's cached copy is still current, so send no body.
  @spec check_get_precondition(nil | {atom(), String.t()}, object()) ::
          :ok | {:error, :not_modified}
  defp check_get_precondition(nil, _object), do: :ok
  defp check_get_precondition({:if_none_match, "*"}, _object), do: {:error, :not_modified}
  defp check_get_precondition({:if_none_match, etag}, %{etag: etag}), do: {:error, :not_modified}
  defp check_get_precondition({:if_none_match, _etag}, _object), do: :ok

  # `if_match: etag` — delete only the exact version the caller last saw.
  @spec check_delete_precondition(nil | {atom(), String.t()}, nil | object()) ::
          :ok | {:error, :precondition_failed}
  defp check_delete_precondition(nil, _current), do: :ok
  defp check_delete_precondition({:if_match, _etag}, nil), do: {:error, :precondition_failed}
  defp check_delete_precondition({:if_match, etag}, %{etag: etag}), do: :ok

  defp check_delete_precondition({:if_match, _etag}, _current) do
    {:error, :precondition_failed}
  end
end