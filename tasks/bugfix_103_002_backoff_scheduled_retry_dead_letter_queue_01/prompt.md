# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

# Backoff-Scheduled Retry Dead Letter Queue

Write me an Elixir GenServer module called `BackoffDLQ` — a dead letter queue where each failed message becomes retry-eligible only after a **backoff delay** that grows with every failed attempt, and where a message that fails too many times is retired to a terminal **dead** state instead of being retried forever.

## Public API

- `BackoffDLQ.start_link(opts)` starts the process.
  - `:clock` — a zero-arity function returning the current time in **milliseconds**. Default `fn -> System.monotonic_time(:millisecond) end`.
  - `:base_backoff_ms` — base backoff in milliseconds (default `1000`).
  - `:max_attempts` — the number of failed retries after which a message becomes `:dead` (default `5`).
  - `:name` — optional process registration name.

- `BackoffDLQ.push(server, queue_name, message, error_reason, metadata)` records a failed message.
  - Records the push time (via the clock), sets `retry_count` to `0`, status to `:pending`, and makes the message **immediately eligible** for retry (`next_retry_at == pushed_at`).
  - Returns `{:ok, message_id}` with an id unique within the server.

- `BackoffDLQ.peek(server, queue_name, count)` returns up to `count` entries, **oldest-first**, without removing them. Each entry is a map including at least `:id`, `:message`, `:error_reason`, `:metadata`, `:retry_count`, `:status` (`:pending` or `:dead`), and `:next_retry_at`. Unknown/empty queue returns `[]`.

- `BackoffDLQ.ready(server, queue_name, count)` returns up to `count` entries, oldest-first, that are **currently retryable**: status `:pending` **and** `now >= next_retry_at`. Dead or not-yet-due entries are excluded.

- `BackoffDLQ.retry(server, queue_name, message_id, handler_fn)` re-attempts one message.
  - Missing id → `{:error, :not_found}`.
  - Status `:dead` → `{:error, :dead}` (handler is **not** invoked).
  - Not yet due (`now < next_retry_at`) → `{:error, :not_ready, ms_remaining}` (handler is **not** invoked).
  - Otherwise invoke `handler_fn.(message)`. Success is `:ok` or `{:ok, term}` → remove the message and return `:ok`.
  - Failure is `{:error, reason}` (return `{:error, reason}`), any other return, or a raised/thrown exception (any `{:error, _}` reason acceptable). On failure the message **stays**, `retry_count` is incremented by 1, and:
    - if the new `retry_count >= max_attempts`, status becomes `:dead`;
    - otherwise `next_retry_at` is set to `now + base_backoff_ms * 2^(retry_count - 1)`.
  - A failing/raising handler must not crash the process.

- `BackoffDLQ.purge(server, queue_name, older_than)` removes messages where `now - pushed_at >= older_than` (age in ms), regardless of status. Returns `{:ok, purged_count}`.

## Notes

- Different `queue_name`s are completely independent.
- Use only the OTP standard library. Single file.

## The buggy module

```elixir
defmodule BackoffDLQ do
  @moduledoc """
  A dead letter queue with exponential backoff-gated retries and a terminal
  `:dead` state after `:max_attempts` failures.
  """

  use GenServer

  ## Client API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc "Pushes a failed `message` with backoff-scheduled retry. Returns `{:ok, id}`."
  @spec push(GenServer.server(), term(), term(), term(), map()) :: {:ok, term()}
  def push(server, queue_name, message, error_reason, metadata) when is_map(metadata) do
    GenServer.call(server, {:push, queue_name, message, error_reason, metadata})
  end

  @spec peek(GenServer.server(), term(), non_neg_integer()) :: [map()]
  def peek(server, queue_name, count) when is_integer(count) and count >= 0 do
    GenServer.call(server, {:peek, queue_name, count})
  end

  @spec ready(GenServer.server(), term(), non_neg_integer()) :: [map()]
  def ready(server, queue_name, count) when is_integer(count) and count >= 0 do
    GenServer.call(server, {:ready, queue_name, count})
  end

  @spec retry(GenServer.server(), term(), term(), (term() -> term())) ::
          :ok | {:error, term()} | {:error, :not_ready, non_neg_integer()}
  def retry(server, queue_name, message_id, handler_fn) when is_function(handler_fn, 1) do
    GenServer.call(server, {:retry, queue_name, message_id, handler_fn})
  end

  @spec purge(GenServer.server(), term(), non_neg_integer()) :: {:ok, non_neg_integer()}
  def purge(server, queue_name, older_than) when is_integer(older_than) do
    GenServer.call(server, {:purge, queue_name, older_than})
  end

  ## Server callbacks

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)

    state = %{
      clock: clock,
      base: Keyword.get(opts, :base_backoff_ms, 1000),
      max_attempts: Keyword.get(opts, :max_attempts, 5),
      next_id: 0,
      queues: %{}
    }

    {:error, state}
  end

  @impl true
  def handle_call({:push, queue, message, error_reason, metadata}, _from, state) do
    id = state.next_id
    now = state.clock.()

    entry = %{
      id: id,
      message: message,
      error_reason: error_reason,
      metadata: metadata,
      retry_count: 0,
      status: :pending,
      pushed_at: now,
      next_retry_at: now
    }

    queues = Map.update(state.queues, queue, [entry], fn es -> es ++ [entry] end)
    {:reply, {:ok, id}, %{state | queues: queues, next_id: id + 1}}
  end

  def handle_call({:peek, queue, count}, _from, state) do
    entries = state.queues |> Map.get(queue, []) |> Enum.take(count) |> Enum.map(&public/1)
    {:reply, entries, state}
  end

  def handle_call({:ready, queue, count}, _from, state) do
    now = state.clock.()

    entries =
      state.queues
      |> Map.get(queue, [])
      |> Enum.filter(fn e -> e.status == :pending and now >= e.next_retry_at end)
      |> Enum.take(count)
      |> Enum.map(&public/1)

    {:reply, entries, state}
  end

  def handle_call({:retry, queue, id, handler}, _from, state) do
    entries = Map.get(state.queues, queue, [])

    case Enum.find(entries, &(&1.id == id)) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{status: :dead} ->
        {:reply, {:error, :dead}, state}

      entry ->
        now = state.clock.()

        if now < entry.next_retry_at do
          {:reply, {:error, :not_ready, entry.next_retry_at - now}, state}
        else
          case run_handler(handler, entry.message) do
            :success ->
              new = Enum.reject(entries, &(&1.id == id))
              {:reply, :ok, put_queue(state, queue, new)}

            {:failure, reason} ->
              rc = entry.retry_count + 1

              updated =
                if rc >= state.max_attempts do
                  %{entry | retry_count: rc, status: :dead}
                else
                  delay = state.base * pow2(rc - 1)
                  %{entry | retry_count: rc, next_retry_at: now + delay}
                end

              new = Enum.map(entries, fn e -> if e.id == id, do: updated, else: e end)
              {:reply, {:error, reason}, put_queue(state, queue, new)}
          end
        end
    end
  end

  def handle_call({:purge, queue, older_than}, _from, state) do
    entries = Map.get(state.queues, queue, [])
    now = state.clock.()
    {kept, purged} = Enum.split_with(entries, fn e -> now - e.pushed_at < older_than end)
    {:reply, {:ok, length(purged)}, put_queue(state, queue, kept)}
  end

  ## Helpers

  defp run_handler(handler, message) do
    case handler.(message) do
      :ok -> :success
      {:ok, _term} -> :success
      {:error, reason} -> {:failure, reason}
      other -> {:failure, {:unexpected_return, other}}
    end
  rescue
    exception -> {:failure, {:handler_raised, exception}}
  catch
    kind, value -> {:failure, {kind, value}}
  end

  defp pow2(n), do: :math.pow(2, n) |> round()

  defp put_queue(state, queue, entries) do
    queues =
      case entries do
        [] -> Map.delete(state.queues, queue)
        _ -> Map.put(state.queues, queue, entries)
      end

    %{state | queues: queues}
  end

  defp public(e) do
    Map.take(e, [
      :id,
      :message,
      :error_reason,
      :metadata,
      :retry_count,
      :status,
      :next_retry_at,
      :pushed_at
    ])
  end
end
```

## Failing test report

```
11 of 11 test(s) failed:

  * test push stores a pending, immediately-ready message
      no match of right hand side value:
      
          {:error,
           %{
             max_attempts: 3,
             next_id: 0,
             base: 1000,
             clock: &BackoffDLQTest.Clock.now/0,
             queues: %{}
           }}
      

  * test peek on unknown queue returns []
      no match of right hand side value:
      
          {:error,
           %{
             max_attempts: 3,
             next_id: 0,
             base: 1000,
             clock: &BackoffDLQTest.Clock.now/0,
             queues: %{}
           }}
      

  * test success removes the message
      no match of right hand side value:
      
          {:error,
           %{
             max_attempts: 3,
             next_id: 0,
             base: 1000,
             clock: &BackoffDLQTest.Clock.now/0,
             queues: %{}
           }}
      

  * test failure bumps retry_count and schedules exponential backoff
      no match of right hand side value:
      
          {:error,
           %{
             max_attempts: 3,
             next_id: 0,
             base: 1000,
             clock: &BackoffDLQTest.Clock.now/0,
             queues: %{}
           }}
      

  (…7 more)
```
