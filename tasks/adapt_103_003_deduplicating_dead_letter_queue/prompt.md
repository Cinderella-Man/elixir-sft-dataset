# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

```elixir
defmodule DLQ do
  @moduledoc """
  A dead letter queue GenServer.

  A dead letter queue is a place to park messages that failed processing so
  they can be inspected (`peek/3`), retried (`retry/4`), or purged (`purge/3`)
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
    Map.take(entry, [:id, :message, :error_reason, :metadata, :retry_count])
  end
end
```

## New specification

# Deduplicating Dead Letter Queue

Write me an Elixir GenServer module called `DedupDLQ` — a dead letter queue that **coalesces** repeated failures of the same logical message. Instead of storing a new entry every time the same failure recurs, it keeps a single entry per **dedup key** and counts how many times that failure has been observed.

## Public API

- `DedupDLQ.start_link(opts)` starts the process.
  - `:clock` — a zero-arity function returning the current time in **milliseconds**. Default `fn -> System.monotonic_time(:millisecond) end`.
  - `:name` — optional process registration name.

- `DedupDLQ.push(server, queue_name, dedup_key, message, error_reason, metadata)` records a failure under a dedup key within the queue.
  - If no entry exists for `dedup_key` in the queue: create one with `occurrences` `1`, `retry_count` `0`, and both `first_seen` and `last_seen` set to the current time. Return `{:ok, :new, message_id}` with a server-unique id (never reused, even after the entry is later removed).
  - If an entry already exists for `dedup_key`: increment its `occurrences`, update `last_seen` to now, and overwrite its `message`, `error_reason`, and `metadata` with the newly supplied (latest) values, while preserving its id, `first_seen`, and `retry_count`. Return `{:ok, :duplicate, existing_message_id}`.

- `DedupDLQ.peek(server, queue_name, count)` returns up to `count` entries, ordered **oldest-first by `first_seen`**, without removing them. Each entry includes at least `:id`, `:dedup_key`, `:message`, `:error_reason`, `:metadata`, `:occurrences`, `:retry_count`, `:first_seen`, and `:last_seen`. Unknown/empty queue → `[]`.

- `DedupDLQ.retry(server, queue_name, dedup_key, handler_fn)` re-attempts one coalesced message by its dedup key.
  - Missing key → `{:error, :not_found}`.
  - Invoke `handler_fn.(message)` with the stored message. Success (`:ok` / `{:ok, term}`) removes the entry and returns `:ok`.
  - Failure (`{:error, reason}`, any other return, or a raised/thrown exception — any `{:error, _}` reason acceptable) keeps the entry, increments its `retry_count` by 1, and returns `{:error, reason}`. For an `{:error, reason}` return, `reason` is that same value. A failing/raising handler must not crash the process.

- `DedupDLQ.purge(server, queue_name, older_than)` removes stale entries by **recency of the last observation**: an entry is removed when `now - last_seen >= older_than` (age in ms). Returns `{:ok, purged_count}`. (Re-pushing a duplicate refreshes `last_seen` and thus protects an entry from purging.)

## Notes

- Different `queue_name`s are completely independent; the same `dedup_key` in two queues is two separate entries.
- Use only the OTP standard library. Single file.
