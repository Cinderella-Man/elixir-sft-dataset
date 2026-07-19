# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `public_entry` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# Dead Letter Queue

Write me an Elixir GenServer module called `DLQ` that acts as a **dead letter queue** — a place to park messages that failed processing so they can be inspected, retried, or purged later.

## Public API

- `DLQ.start_link(opts)` starts the process.
  - It must accept a `:clock` option: a zero-arity function returning the current time in **milliseconds**. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`.
  - It must accept a `:name` option for process registration (optional). When given, register the process under that name so it is reachable via `Process.whereis/1` and usable as the `server` argument to the other functions.

- `DLQ.push(server, queue_name, message, error_reason, metadata)` records a failed message under the given queue.
  - `message` is arbitrary term, `error_reason` is arbitrary term, `metadata` is an arbitrary map.
  - Record the time the message was pushed (using the configured clock) and initialize its retry count to `0`.
  - Return `{:ok, message_id}` where `message_id` is an integer, reference, or binary string, and is unique within the server (two pushes never collide, even across different queues in the same server).

- `DLQ.peek(server, queue_name, count)` returns the failed messages currently held for `queue_name` **without removing them**.
  - Return a list of at most `count` entries, ordered **oldest-first** (the earliest pushed message first). A `count` of `0` returns `[]`.
  - Each entry is a map that includes at least these keys:
    - `:id` — the message id returned by `push`
    - `:message` — the original message term
    - `:error_reason` — the original error reason term
    - `:metadata` — the metadata map
    - `:retry_count` — how many times a retry has failed for this message (starts at `0`)
  - For an unknown or empty queue, return `[]`.

- `DLQ.retry(server, queue_name, message_id, handler_fn)` re-attempts processing of one message.
  - Look up the message by `message_id` within `queue_name`. If it does not exist in that queue, return `{:error, :not_found}` **without invoking `handler_fn`** (a message id from a different queue counts as not found here).
  - Otherwise invoke `handler_fn.(message)` with the stored `message`.
  - **Success** is when the handler returns `:ok` or `{:ok, term}`. On success, remove the message from the queue and return `:ok`.
  - **Failure** is when the handler returns `{:error, reason}` (return `{:error, reason}`), or raises an exception, or returns anything else. On failure, the message **stays** in the queue, its `:retry_count` is **incremented by 1**, and `retry` returns `{:error, reason}` (for a raised exception or an unexpected return value, any `{:error, _}` reason is acceptable).
  - A failing or raising handler must **not** crash the `DLQ` process; the server stays alive and usable for subsequent calls.

- `DLQ.purge(server, queue_name, older_than)` removes stale messages from `queue_name`.
  - `older_than` is an **age in milliseconds**. A message is removed when `now - pushed_at >= older_than`, where `now` comes from the configured clock and `pushed_at` is when the message was pushed.
  - Return `{:ok, purged_count}` — the number of messages removed.

## Notes

- Different `queue_name`s are completely independent; operating on one must never affect another.
- Use only the OTP standard library, no external dependencies.
- Give me the complete module in a single file.

## The module with `public_entry` missing

```elixir
defmodule DLQ do
  @moduledoc """
  A dead letter queue GenServer.

  A dead letter queue is a place to park messages that failed processing so
  they can be inspected (`peek/3`), retried (`retry/4`), or purged (`purge/4`)
  later.

  Messages are grouped by an arbitrary `queue_name`. Different queues are
  completely independent — operating on one never affects another.

  Each stored message records the time it was pushed (via a configurable clock)
  and a retry count that starts at `0` and is incremented every time a retry
  fails.
  """

  use GenServer

  ## Client API

  @doc """
  Start the dead letter queue process.

  ## Options

    * `:clock` — a zero-arity function returning the current time in
      milliseconds. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:name` — optional name for process registration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    gen_opts =
      case name do
        nil -> []
        name -> [name: name]
      end

    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Record a failed `message` under `queue_name`.

  Returns `{:ok, message_id}` where `message_id` is unique within the server.
  """
  @spec push(GenServer.server(), term(), term(), term(), map()) :: {:ok, term()}
  def push(server, queue_name, message, error_reason, metadata)
      when is_map(metadata) do
    GenServer.call(server, {:push, queue_name, message, error_reason, metadata})
  end

  @doc """
  Return up to `count` messages held for `queue_name`, oldest-first, without
  removing them. Unknown or empty queues return `[]`.
  """
  @spec peek(GenServer.server(), term(), non_neg_integer()) :: [map()]
  def peek(server, queue_name, count)
      when is_integer(count) and count >= 0 do
    GenServer.call(server, {:peek, queue_name, count})
  end

  @doc """
  Re-attempt processing of one message by `message_id` within `queue_name`.

  `handler_fn` is invoked with the stored message. Success is `:ok` or
  `{:ok, term}`, in which case the message is removed and `:ok` is returned.
  Any other return value, an `{:error, reason}`, or a raised exception is a
  failure: the message stays, its retry count is incremented, and
  `{:error, reason}` is returned.
  """
  @spec retry(GenServer.server(), term(), term(), (term() -> term())) ::
          :ok | {:error, term()}
  def retry(server, queue_name, message_id, handler_fn)
      when is_function(handler_fn, 1) do
    GenServer.call(server, {:retry, queue_name, message_id, handler_fn})
  end

  @doc """
  Remove messages from `queue_name` whose age is at least `older_than`
  milliseconds. Returns `{:ok, purged_count}`.
  """
  @spec purge(GenServer.server(), term(), non_neg_integer()) ::
          {:ok, non_neg_integer()}
  def purge(server, queue_name, older_than)
      when is_integer(older_than) do
    GenServer.call(server, {:purge, queue_name, older_than})
  end

  ## Server callbacks

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)

    state = %{
      clock: clock,
      next_id: 0,
      # queue_name => list of entries, kept in oldest-first insertion order
      queues: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:push, queue_name, message, error_reason, metadata}, _from, state) do
    id = state.next_id

    entry = %{
      id: id,
      message: message,
      error_reason: error_reason,
      metadata: metadata,
      retry_count: 0,
      pushed_at: state.clock.()
    }

    queues = Map.update(state.queues, queue_name, [entry], fn entries -> entries ++ [entry] end)
    state = %{state | queues: queues, next_id: id + 1}

    {:reply, {:ok, id}, state}
  end

  @impl true
  def handle_call({:peek, queue_name, count}, _from, state) do
    entries =
      state.queues
      |> Map.get(queue_name, [])
      |> Enum.take(count)
      |> Enum.map(&public_entry/1)

    {:reply, entries, state}
  end

  @impl true
  def handle_call({:retry, queue_name, message_id, handler_fn}, _from, state) do
    entries = Map.get(state.queues, queue_name, [])

    case Enum.find(entries, fn entry -> entry.id == message_id end) do
      nil ->
        {:reply, {:error, :not_found}, state}

      entry ->
        case run_handler(handler_fn, entry.message) do
          :success ->
            new_entries = Enum.reject(entries, fn e -> e.id == message_id end)
            state = put_queue(state, queue_name, new_entries)
            {:reply, :ok, state}

          {:failure, reason} ->
            new_entries =
              Enum.map(entries, fn
                %{id: ^message_id} = e -> %{e | retry_count: e.retry_count + 1}
                e -> e
              end)

            state = put_queue(state, queue_name, new_entries)
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:purge, queue_name, older_than}, _from, state) do
    entries = Map.get(state.queues, queue_name, [])
    now = state.clock.()

    {kept, purged} =
      Enum.split_with(entries, fn entry ->
        now - entry.pushed_at < older_than
      end)

    state = put_queue(state, queue_name, kept)
    {:reply, {:ok, length(purged)}, state}
  end

  ## Helpers

  defp run_handler(handler_fn, message) do
    case handler_fn.(message) do
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

  defp put_queue(state, queue_name, entries) do
    queues =
      case entries do
        [] -> Map.delete(state.queues, queue_name)
        _ -> Map.put(state.queues, queue_name, entries)
      end

    %{state | queues: queues}
  end

  defp public_entry(entry) do
    # TODO
  end
end
```

Give me only the complete implementation of `public_entry` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
