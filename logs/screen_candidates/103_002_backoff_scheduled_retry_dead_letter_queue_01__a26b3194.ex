defmodule BackoffDLQ do
  @moduledoc """
  A dead letter queue with exponential backoff scheduling and terminal death.

  Each failed message is stored under a queue name with a `retry_count`, a
  `status` (`:pending` or `:dead`) and a `next_retry_at` timestamp. A freshly
  pushed message is immediately eligible for retry. Every failed retry attempt
  increments `retry_count` and pushes `next_retry_at` further into the future
  using an exponential backoff of `base_backoff_ms * 2^(retry_count - 1)`.

  Once a message has failed `max_attempts` times it is retired to the terminal
  `:dead` status and is never retried again (though it can still be inspected
  with `peek/3` or removed with `purge/3`).

  Time is supplied by an injectable zero-arity `:clock` function returning
  milliseconds, which makes the backoff behaviour deterministically testable.

  Queues identified by different names are completely independent of each other.
  """

  use GenServer

  @type queue_name :: term()
  @type message_id :: pos_integer()
  @type status :: :pending | :dead

  @type entry :: %{
          id: message_id(),
          queue: queue_name(),
          message: term(),
          error_reason: term(),
          metadata: term(),
          retry_count: non_neg_integer(),
          status: status(),
          pushed_at: integer(),
          next_retry_at: integer()
        }

  @default_base_backoff_ms 1_000
  @default_max_attempts 5

  # --- Public API ---------------------------------------------------------

  @doc """
  Starts the dead letter queue process.

  ## Options

    * `:clock` - zero-arity function returning current time in milliseconds.
      Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:base_backoff_ms` - base backoff in milliseconds (default `1000`).
    * `:max_attempts` - failed retries after which a message becomes `:dead`
      (default `5`).
    * `:name` - optional process registration name.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Records a failed `message` in `queue_name` along with its `error_reason` and
  arbitrary `metadata`.

  The message starts with `retry_count` `0`, status `:pending` and is
  immediately eligible for retry. Returns `{:ok, message_id}`.
  """
  @spec push(GenServer.server(), queue_name(), term(), term(), term()) :: {:ok, message_id()}
  def push(server, queue_name, message, error_reason, metadata \\ %{}) do
    GenServer.call(server, {:push, queue_name, message, error_reason, metadata})
  end

  @doc """
  Returns up to `count` entries from `queue_name`, oldest-first, without
  removing them. Entries of any status are included. Returns `[]` for unknown
  or empty queues.
  """
  @spec peek(GenServer.server(), queue_name(), non_neg_integer()) :: [entry()]
  def peek(server, queue_name, count) do
    GenServer.call(server, {:peek, queue_name, count})
  end

  @doc """
  Returns up to `count` currently retryable entries from `queue_name`,
  oldest-first: status `:pending` and `now >= next_retry_at`.

  Dead entries and entries whose backoff has not elapsed are excluded.
  """
  @spec ready(GenServer.server(), queue_name(), non_neg_integer()) :: [entry()]
  def ready(server, queue_name, count) do
    GenServer.call(server, {:ready, queue_name, count})
  end

  @doc """
  Re-attempts the message `message_id` in `queue_name` by invoking
  `handler_fn.(message)`.

  Returns:

    * `{:error, :not_found}` if the id is unknown.
    * `{:error, :dead}` if the message is in the terminal `:dead` status.
    * `{:error, :not_ready, ms_remaining}` if the backoff has not yet elapsed.
    * `:ok` if the handler returns `:ok` or `{:ok, term}`; the message is
      removed.
    * `{:error, reason}` if the handler fails, raises or throws; the message is
      kept, its `retry_count` incremented and its backoff rescheduled (or the
      message retired to `:dead` once `max_attempts` is reached).
  """
  @spec retry(GenServer.server(), queue_name(), message_id(), (term() -> term())) ::
          :ok | {:error, term()} | {:error, :not_ready, non_neg_integer()}
  def retry(server, queue_name, message_id, handler_fn) when is_function(handler_fn, 1) do
    GenServer.call(server, {:retry, queue_name, message_id, handler_fn})
  end

  @doc """
  Removes every message in `queue_name` whose age (`now - pushed_at`) is at
  least `older_than` milliseconds, regardless of status.

  Returns `{:ok, purged_count}`.
  """
  @spec purge(GenServer.server(), queue_name(), non_neg_integer()) :: {:ok, non_neg_integer()}
  def purge(server, queue_name, older_than) do
    GenServer.call(server, {:purge, queue_name, older_than})
  end

  # --- GenServer callbacks ------------------------------------------------

  @impl true
  def init(opts) do
    state = %{
      clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end),
      base_backoff_ms: Keyword.get(opts, :base_backoff_ms, @default_base_backoff_ms),
      max_attempts: Keyword.get(opts, :max_attempts, @default_max_attempts),
      next_id: 1,
      # queue_name => [entry] kept in insertion (oldest-first) order
      queues: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:push, queue_name, message, error_reason, metadata}, _from, state) do
    now = now(state)
    id = state.next_id

    entry = %{
      id: id,
      queue: queue_name,
      message: message,
      error_reason: error_reason,
      metadata: metadata,
      retry_count: 0,
      status: :pending,
      pushed_at: now,
      next_retry_at: now
    }

    entries = Map.get(state.queues, queue_name, []) ++ [entry]
    queues = Map.put(state.queues, queue_name, entries)

    {:reply, {:ok, id}, %{state | queues: queues, next_id: id + 1}}
  end

  def handle_call({:peek, queue_name, count}, _from, state) do
    entries =
      state.queues
      |> Map.get(queue_name, [])
      |> take(count)

    {:reply, entries, state}
  end

  def handle_call({:ready, queue_name, count}, _from, state) do
    now = now(state)

    entries =
      state.queues
      |> Map.get(queue_name, [])
      |> Enum.filter(&ready?(&1, now))
      |> take(count)

    {:reply, entries, state}
  end

  def handle_call({:retry, queue_name, message_id, handler_fn}, _from, state) do
    entries = Map.get(state.queues, queue_name, [])

    case Enum.find(entries, &(&1.id == message_id)) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{status: :dead} ->
        {:reply, {:error, :dead}, state}

      entry ->
        now = now(state)

        if now < entry.next_retry_at do
          {:reply, {:error, :not_ready, entry.next_retry_at - now}, state}
        else
          do_retry(entry, handler_fn, queue_name, entries, now, state)
        end
    end
  end

  def handle_call({:purge, queue_name, older_than}, _from, state) do
    now = now(state)
    entries = Map.get(state.queues, queue_name, [])

    {purged, kept} = Enum.split_with(entries, &(now - &1.pushed_at >= older_than))
    queues = Map.put(state.queues, queue_name, kept)

    {:reply, {:ok, length(purged)}, %{state | queues: queues}}
  end

  # --- Internals ----------------------------------------------------------

  defp do_retry(entry, handler_fn, queue_name, entries, now, state) do
    case safe_invoke(handler_fn, entry.message) do
      :ok ->
        kept = Enum.reject(entries, &(&1.id == entry.id))
        queues = Map.put(state.queues, queue_name, kept)
        {:reply, :ok, %{state | queues: queues}}

      {:error, reason} ->
        updated = apply_failure(entry, now, state)
        kept = Enum.map(entries, fn e -> if e.id == entry.id, do: updated, else: e end)
        queues = Map.put(state.queues, queue_name, kept)
        {:reply, {:error, reason}, %{state | queues: queues}}
    end
  end

  # Normalises any handler outcome into `:ok` or `{:error, reason}`.
  defp safe_invoke(handler_fn, message) do
    case handler_fn.(message) do
      :ok -> :ok
      {:ok, _term} -> :ok
      {:error, reason} -> {:error, reason}
      other -> {:error, {:invalid_return, other}}
    end
  rescue
    exception -> {:error, {:exception, exception}}
  catch
    :throw, value -> {:error, {:throw, value}}
    :exit, value -> {:error, {:exit, value}}
  end

  defp apply_failure(entry, now, state) do
    retry_count = entry.retry_count + 1

    if retry_count >= state.max_attempts do
      %{entry | retry_count: retry_count, status: :dead}
    else
      backoff = state.base_backoff_ms * Integer.pow(2, retry_count - 1)
      %{entry | retry_count: retry_count, next_retry_at: now + backoff}
    end
  end

  defp ready?(%{status: :pending} = entry, now), do: now >= entry.next_retry_at
  defp ready?(_entry, _now), do: false

  defp take(_entries, count) when not is_integer(count) or count <= 0, do: []
  defp take(entries, count), do: Enum.take(entries, count)

  defp now(state), do: state.clock.()
end