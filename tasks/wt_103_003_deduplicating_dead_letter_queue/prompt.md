# Write tests for this module

Below is a completed Elixir module and the original specification it was built to
satisfy. Write a comprehensive ExUnit test harness that verifies a correct
implementation of this module.

Requirements for the harness:
- Define a module `<Module>Test` that does `use ExUnit.Case, async: false`.
- Do NOT call `ExUnit.start()` — the evaluator starts ExUnit itself.
- Make it self-contained: any fakes, clock Agents, or helpers are defined inline.
- Cover the full public API and the important edge cases described in the spec.
- It must compile with ZERO warnings (prefix unused variables with `_`; match float
  zero as `+0.0`/`-0.0`).
- Give me the complete harness in a single file.

## Original specification

# Deduplicating Dead Letter Queue

Write me an Elixir GenServer module called `DedupDLQ` — a dead letter queue that **coalesces** repeated failures of the same logical message. Instead of storing a new entry every time the same failure recurs, it keeps a single entry per **dedup key** and counts how many times that failure has been observed.

## Public API

- `DedupDLQ.start_link(opts)` starts the process.
  - `:clock` — a zero-arity function returning the current time in **milliseconds**. Default `fn -> System.monotonic_time(:millisecond) end`.
  - `:name` — optional process registration name.

- `DedupDLQ.push(server, queue_name, dedup_key, message, error_reason, metadata)` records a failure under a dedup key within the queue.
  - If no entry exists for `dedup_key` in the queue: create one with `occurrences` `1`, `retry_count` `0`, and both `first_seen` and `last_seen` set to the current time. Return `{:ok, :new, message_id}` with a server-unique id.
  - If an entry already exists for `dedup_key`: increment its `occurrences`, update `last_seen` to now, and overwrite its `message`, `error_reason`, and `metadata` with the newly supplied (latest) values, while preserving its id, `first_seen`, and `retry_count`. Return `{:ok, :duplicate, existing_message_id}`.

- `DedupDLQ.peek(server, queue_name, count)` returns up to `count` entries, ordered **oldest-first by `first_seen`**, without removing them. Each entry includes at least `:id`, `:dedup_key`, `:message`, `:error_reason`, `:metadata`, `:occurrences`, `:retry_count`, `:first_seen`, and `:last_seen`. Unknown/empty queue → `[]`.

- `DedupDLQ.retry(server, queue_name, dedup_key, handler_fn)` re-attempts one coalesced message by its dedup key.
  - Missing key → `{:error, :not_found}`.
  - Invoke `handler_fn.(message)` with the stored message. Success (`:ok` / `{:ok, term}`) removes the entry and returns `:ok`.
  - Failure (`{:error, reason}`, any other return, or a raised/thrown exception — any `{:error, _}` reason acceptable) keeps the entry, increments its `retry_count` by 1, and returns `{:error, reason}`. A failing/raising handler must not crash the process.

- `DedupDLQ.purge(server, queue_name, older_than)` removes stale entries by **recency of the last observation**: an entry is removed when `now - last_seen >= older_than` (age in ms). Returns `{:ok, purged_count}`. (Re-pushing a duplicate refreshes `last_seen` and thus protects an entry from purging.)

## Notes

- Different `queue_name`s are completely independent; the same `dedup_key` in two queues is two separate entries.
- Use only the OTP standard library. Single file.

## Module under test

```elixir
defmodule DedupDLQ do
  @moduledoc """
  A dead letter queue that coalesces repeated failures of the same logical
  message by a `dedup_key`, tracking an occurrence count and first/last-seen
  timestamps instead of storing duplicate entries.
  """

  use GenServer

  ## Client API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @spec push(GenServer.server(), term(), term(), term(), term(), map()) ::
          {:ok, :new | :duplicate, term()}
  def push(server, queue_name, dedup_key, message, error_reason, metadata)
      when is_map(metadata) do
    GenServer.call(server, {:push, queue_name, dedup_key, message, error_reason, metadata})
  end

  @spec peek(GenServer.server(), term(), non_neg_integer()) :: [map()]
  def peek(server, queue_name, count) when is_integer(count) and count >= 0 do
    GenServer.call(server, {:peek, queue_name, count})
  end

  @spec retry(GenServer.server(), term(), term(), (term() -> term())) ::
          :ok | {:error, term()}
  def retry(server, queue_name, dedup_key, handler_fn) when is_function(handler_fn, 1) do
    GenServer.call(server, {:retry, queue_name, dedup_key, handler_fn})
  end

  @spec purge(GenServer.server(), term(), non_neg_integer()) :: {:ok, non_neg_integer()}
  def purge(server, queue_name, older_than) when is_integer(older_than) do
    GenServer.call(server, {:purge, queue_name, older_than})
  end

  ## Server callbacks

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    {:ok, %{clock: clock, next_id: 0, queues: %{}}}
  end

  @impl true
  def handle_call({:push, queue, key, message, error_reason, metadata}, _from, state) do
    entries = Map.get(state.queues, queue, [])
    now = state.clock.()

    case Enum.find(entries, &(&1.dedup_key == key)) do
      nil ->
        id = state.next_id

        entry = %{
          id: id,
          dedup_key: key,
          message: message,
          error_reason: error_reason,
          metadata: metadata,
          occurrences: 1,
          retry_count: 0,
          first_seen: now,
          last_seen: now
        }

        state = put_queue(%{state | next_id: id + 1}, queue, entries ++ [entry])
        {:reply, {:ok, :new, id}, state}

      existing ->
        updated = %{
          existing
          | occurrences: existing.occurrences + 1,
            last_seen: now,
            message: message,
            error_reason: error_reason,
            metadata: metadata
        }

        new = Enum.map(entries, fn e -> if e.dedup_key == key, do: updated, else: e end)
        {:reply, {:ok, :duplicate, existing.id}, put_queue(state, queue, new)}
    end
  end

  def handle_call({:peek, queue, count}, _from, state) do
    entries = state.queues |> Map.get(queue, []) |> Enum.take(count) |> Enum.map(&public/1)
    {:reply, entries, state}
  end

  def handle_call({:retry, queue, key, handler}, _from, state) do
    entries = Map.get(state.queues, queue, [])

    case Enum.find(entries, &(&1.dedup_key == key)) do
      nil ->
        {:reply, {:error, :not_found}, state}

      entry ->
        case run_handler(handler, entry.message) do
          :success ->
            new = Enum.reject(entries, &(&1.dedup_key == key))
            {:reply, :ok, put_queue(state, queue, new)}

          {:failure, reason} ->
            new =
              Enum.map(entries, fn
                %{dedup_key: ^key} = e -> %{e | retry_count: e.retry_count + 1}
                e -> e
              end)

            {:reply, {:error, reason}, put_queue(state, queue, new)}
        end
    end
  end

  def handle_call({:purge, queue, older_than}, _from, state) do
    entries = Map.get(state.queues, queue, [])
    now = state.clock.()
    {kept, purged} = Enum.split_with(entries, fn e -> now - e.last_seen < older_than end)
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
      :dedup_key,
      :message,
      :error_reason,
      :metadata,
      :occurrences,
      :retry_count,
      :first_seen,
      :last_seen
    ])
  end
end
```
