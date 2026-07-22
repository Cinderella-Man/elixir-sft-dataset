defmodule DedupDLQ do
  @moduledoc """
  A deduplicating dead letter queue (DLQ) implemented as a `GenServer`.

  Unlike a plain DLQ that appends a new entry for every failure, `DedupDLQ`
  *coalesces* repeated failures of the same logical message. Each failure is
  recorded under a `dedup_key` scoped to a `queue_name`; if an entry for that
  key already exists, its occurrence counter is incremented and its payload is
  refreshed with the latest observation instead of a new entry being stored.

  Each stored entry carries:

    * `:id` — server-unique identifier assigned at creation time
    * `:dedup_key` — the logical key the failure was coalesced under
    * `:message` — the most recently pushed message payload
    * `:error_reason` — the most recently pushed error reason
    * `:metadata` — the most recently pushed metadata
    * `:occurrences` — how many times this failure has been observed
    * `:retry_count` — how many times a retry of this entry has failed
    * `:first_seen` — timestamp (ms) of the first observation
    * `:last_seen` — timestamp (ms) of the most recent observation

  Queues are fully independent: the same `dedup_key` in two different queues
  refers to two separate entries.

  Time is supplied by an injectable `:clock` function (a zero-arity function
  returning milliseconds), which makes purging and aging deterministically
  testable.

  ## Example

      {:ok, dlq} = DedupDLQ.start_link([])

      {:ok, :new, id} = DedupDLQ.push(dlq, :emails, "user:1", %{to: "a@b.c"},
                                      :timeout, %{attempt: 1})
      {:ok, :duplicate, ^id} = DedupDLQ.push(dlq, :emails, "user:1", %{to: "a@b.c"},
                                             :timeout, %{attempt: 2})

      [entry] = DedupDLQ.peek(dlq, :emails, 10)
      entry.occurrences
      #=> 2

      DedupDLQ.retry(dlq, :emails, "user:1", fn _message -> :ok end)
      #=> :ok
  """

  use GenServer

  @typedoc "Name identifying an independent queue."
  @type queue_name :: term()

  @typedoc "Key used to coalesce repeated failures of the same logical message."
  @type dedup_key :: term()

  @typedoc "Server-unique identifier of a coalesced entry."
  @type message_id :: pos_integer()

  @typedoc "A coalesced dead letter entry."
  @type entry :: %{
          id: message_id(),
          dedup_key: dedup_key(),
          message: term(),
          error_reason: term(),
          metadata: term(),
          occurrences: pos_integer(),
          retry_count: non_neg_integer(),
          first_seen: integer(),
          last_seen: integer()
        }

  @typedoc "Function invoked with a stored message when retrying an entry."
  @type handler_fun :: (term() -> term())

  @typedoc "Server reference accepted by the public API."
  @type server :: GenServer.server()

  defmodule State do
    @moduledoc false

    defstruct clock: nil, next_id: 1, queues: %{}
  end

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the dead letter queue process.

  ## Options

    * `:clock` — zero-arity function returning the current time in milliseconds.
      Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:name` — optional name to register the process under. Any other option is
      passed through to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    {clock, opts} = Keyword.pop(opts, :clock, &default_clock/0)
    GenServer.start_link(__MODULE__, clock, opts)
  end

  @doc """
  Records a failure under `dedup_key` inside `queue_name`.

  When no entry exists for the key, a new one is created with `occurrences` of
  `1`, `retry_count` of `0`, and `first_seen`/`last_seen` both set to now;
  `{:ok, :new, message_id}` is returned.

  When an entry already exists, its `occurrences` is incremented, `last_seen` is
  refreshed, and `message`, `error_reason` and `metadata` are overwritten with
  the values supplied here. The entry's `id`, `first_seen` and `retry_count` are
  preserved and `{:ok, :duplicate, existing_message_id}` is returned.
  """
  @spec push(server(), queue_name(), dedup_key(), term(), term(), term()) ::
          {:ok, :new | :duplicate, message_id()}
  def push(server, queue_name, dedup_key, message, error_reason, metadata) do
    GenServer.call(server, {:push, queue_name, dedup_key, message, error_reason, metadata})
  end

  @doc """
  Returns up to `count` entries from `queue_name` without removing them.

  Entries are ordered oldest-first by `first_seen`. An unknown or empty queue,
  or a non-positive `count`, yields `[]`.
  """
  @spec peek(server(), queue_name(), non_neg_integer()) :: [entry()]
  def peek(server, queue_name, count) when is_integer(count) do
    GenServer.call(server, {:peek, queue_name, count})
  end

  @doc """
  Re-attempts the coalesced message stored under `dedup_key` in `queue_name`.

  `handler_fun` is invoked with the stored message. If it returns `:ok` or
  `{:ok, term}`, the entry is removed and `:ok` is returned.

  If it returns `{:error, reason}`, returns anything else, or raises/throws/exits,
  the entry is kept, its `retry_count` is incremented by one, and
  `{:error, reason}` is returned. A misbehaving handler never crashes the server.

  Returns `{:error, :not_found}` when no entry exists for the key.
  """
  @spec retry(server(), queue_name(), dedup_key(), handler_fun()) :: :ok | {:error, term()}
  def retry(server, queue_name, dedup_key, handler_fun) when is_function(handler_fun, 1) do
    GenServer.call(server, {:retry, queue_name, dedup_key, handler_fun})
  end

  @doc """
  Removes stale entries from `queue_name` based on the recency of the last
  observation.

  An entry is purged when `now - last_seen >= older_than` (both in milliseconds).
  Because re-pushing a duplicate refreshes `last_seen`, actively recurring
  failures are protected from purging.

  Returns `{:ok, purged_count}`.
  """
  @spec purge(server(), queue_name(), non_neg_integer()) :: {:ok, non_neg_integer()}
  def purge(server, queue_name, older_than) when is_integer(older_than) do
    GenServer.call(server, {:purge, queue_name, older_than})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(clock) when is_function(clock, 0) do
    {:ok, %State{clock: clock, next_id: 1, queues: %{}}}
  end

  @impl GenServer
  def handle_call({:push, queue_name, dedup_key, message, error_reason, metadata}, _from, state) do
    now = now(state)
    queue = Map.get(state.queues, queue_name, %{})

    case Map.fetch(queue, dedup_key) do
      {:ok, existing} ->
        updated = %{
          existing
          | message: message,
            error_reason: error_reason,
            metadata: metadata,
            occurrences: existing.occurrences + 1,
            last_seen: now
        }

        state = put_queue(state, queue_name, Map.put(queue, dedup_key, updated))
        {:reply, {:ok, :duplicate, updated.id}, state}

      :error ->
        id = state.next_id

        entry = %{
          id: id,
          dedup_key: dedup_key,
          message: message,
          error_reason: error_reason,
          metadata: metadata,
          occurrences: 1,
          retry_count: 0,
          first_seen: now,
          last_seen: now
        }

        state =
          state
          |> put_queue(queue_name, Map.put(queue, dedup_key, entry))
          |> Map.put(:next_id, id + 1)

        {:reply, {:ok, :new, id}, state}
    end
  end

  @impl GenServer
  def handle_call({:peek, queue_name, count}, _from, state) when count <= 0 do
    _ = queue_name
    {:reply, [], state}
  end

  def handle_call({:peek, queue_name, count}, _from, state) do
    entries =
      state.queues
      |> Map.get(queue_name, %{})
      |> Map.values()
      |> Enum.sort_by(&{&1.first_seen, &1.id})
      |> Enum.take(count)

    {:reply, entries, state}
  end

  def handle_call({:retry, queue_name, dedup_key, handler_fun}, _from, state) do
    queue = Map.get(state.queues, queue_name, %{})

    case Map.fetch(queue, dedup_key) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, entry} ->
        case safe_invoke(handler_fun, entry.message) do
          :ok ->
            state = put_queue(state, queue_name, Map.delete(queue, dedup_key))
            {:reply, :ok, state}

          {:error, reason} ->
            bumped = %{entry | retry_count: entry.retry_count + 1}
            state = put_queue(state, queue_name, Map.put(queue, dedup_key, bumped))
            {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call({:purge, queue_name, older_than}, _from, state) do
    now = now(state)
    queue = Map.get(state.queues, queue_name, %{})

    kept =
      Enum.reject(queue, fn {_key, entry} ->
        now - entry.last_seen >= older_than
      end)
      |> Map.new()

    purged = map_size(queue) - map_size(kept)
    {:reply, {:ok, purged}, put_queue(state, queue_name, kept)}
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  @spec default_clock() :: integer()
  defp default_clock, do: System.monotonic_time(:millisecond)

  @spec now(State.t()) :: integer()
  defp now(%State{clock: clock}), do: clock.()

  @spec put_queue(State.t(), queue_name(), map()) :: State.t()
  defp put_queue(state, queue_name, queue) when map_size(queue) == 0 do
    %{state | queues: Map.delete(state.queues, queue_name)}
  end

  defp put_queue(state, queue_name, queue) do
    %{state | queues: Map.put(state.queues, queue_name, queue)}
  end

  # Normalizes every possible handler outcome into `:ok` or `{:error, reason}`,
  # so that a badly behaved handler can never take the server down.
  @spec safe_invoke(handler_fun(), term()) :: :ok | {:error, term()}
  defp safe_invoke(handler_fun, message) do
    case handler_fun.(message) do
      :ok -> :ok
      {:ok, _term} -> :ok
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected_return, other}}
    end
  rescue
    exception -> {:error, {:exception, exception}}
  catch
    :throw, value -> {:error, {:throw, value}}
    :exit, reason -> {:error, {:exit, reason}}
  end
end