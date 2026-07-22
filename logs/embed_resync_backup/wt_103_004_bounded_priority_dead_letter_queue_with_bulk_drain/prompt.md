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

# Bounded Priority Dead Letter Queue with Bulk Drain

Write me an Elixir GenServer module called `PriorityDLQ` — a dead letter queue where each parked message carries a **priority**, the queue has a bounded **capacity** per queue name, and messages can be reprocessed in bulk via a **drain** operation that walks entries in priority order.

## Public API

- `PriorityDLQ.start_link(opts)` starts the process.
  - `:clock` — a zero-arity function returning the current time in **milliseconds**. Default `fn -> System.monotonic_time(:millisecond) end`.
  - `:capacity` — the maximum number of entries **per queue name** (a positive integer, or `:infinity` for unbounded; default `:infinity`).
  - `:name` — optional process registration name.

- `PriorityDLQ.push(server, queue_name, message, error_reason, metadata, priority)` records a failed message. `priority` is one of `:high`, `:normal`, `:low`.
  - Records the push time, `retry_count` `0`, and the given priority.
  - If the target queue already holds `capacity` entries, reject with `{:error, :full}` (nothing is stored).
  - Otherwise return `{:ok, message_id}` with a server-unique id.

- `PriorityDLQ.peek(server, queue_name, count)` returns up to `count` entries **without removing them**, ordered **highest-priority-first** (`:high` > `:normal` > `:low`), and **FIFO within the same priority** (earliest pushed first). Each entry includes at least `:id`, `:message`, `:error_reason`, `:metadata`, `:priority`, and `:retry_count`. Unknown/empty queue → `[]`.

- `PriorityDLQ.drain(server, queue_name, handler_fn, count)` reprocesses up to `count` messages, visiting them in the same **priority-then-FIFO** order as `peek`.
  - For each visited message, invoke `handler_fn.(message)`. Success (`:ok` / `{:ok, term}`) removes it; failure (`{:error, reason}`, any other return, or a raised/thrown exception) keeps it and increments its `retry_count` by 1.
  - A failing/raising handler must not crash the process.
  - Returns `{:ok, %{succeeded: s, failed: f, processed: [id, ...]}}` where `processed` lists the visited ids in the order they were handled.

- `PriorityDLQ.purge(server, queue_name, older_than)` removes messages where `now - pushed_at >= older_than` (age in ms). Returns `{:ok, purged_count}`.

## Notes

- Different `queue_name`s are completely independent, including their capacity budgets.
- Use only the OTP standard library. Single file.

## Module under test

```elixir
defmodule PriorityDLQ do
  @moduledoc """
  A bounded, priority-ordered dead letter queue supporting bulk reprocessing
  via `drain/4`. Entries are visited highest-priority-first, FIFO within a
  priority level.
  """

  use GenServer

  @rank %{high: 3, normal: 2, low: 1}

  ## Client API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @spec push(GenServer.server(), term(), term(), term(), map(), :high | :normal | :low) ::
          {:ok, term()} | {:error, :full}
  def push(server, queue_name, message, error_reason, metadata, priority)
      when is_map(metadata) and priority in [:high, :normal, :low] do
    GenServer.call(server, {:push, queue_name, message, error_reason, metadata, priority})
  end

  @spec peek(GenServer.server(), term(), non_neg_integer()) :: [map()]
  def peek(server, queue_name, count) when is_integer(count) and count >= 0 do
    GenServer.call(server, {:peek, queue_name, count})
  end

  @spec drain(GenServer.server(), term(), (term() -> term()), non_neg_integer()) ::
          {:ok, %{succeeded: non_neg_integer(), failed: non_neg_integer(), processed: [term()]}}
  def drain(server, queue_name, handler_fn, count)
      when is_function(handler_fn, 1) and is_integer(count) and count >= 0 do
    GenServer.call(server, {:drain, queue_name, handler_fn, count})
  end

  @spec purge(GenServer.server(), term(), non_neg_integer()) :: {:ok, non_neg_integer()}
  def purge(server, queue_name, older_than) when is_integer(older_than) do
    GenServer.call(server, {:purge, queue_name, older_than})
  end

  ## Server callbacks

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    capacity = Keyword.get(opts, :capacity, :infinity)
    {:ok, %{clock: clock, capacity: capacity, next_id: 0, queues: %{}}}
  end

  @impl true
  def handle_call({:push, queue, message, error_reason, metadata, priority}, _from, state) do
    entries = Map.get(state.queues, queue, [])

    if full?(state.capacity, length(entries)) do
      {:reply, {:error, :full}, state}
    else
      id = state.next_id

      entry = %{
        id: id,
        message: message,
        error_reason: error_reason,
        metadata: metadata,
        priority: priority,
        retry_count: 0,
        pushed_at: state.clock.()
      }

      state = put_queue(%{state | next_id: id + 1}, queue, entries ++ [entry])
      {:reply, {:ok, id}, state}
    end
  end

  def handle_call({:peek, queue, count}, _from, state) do
    entries =
      state.queues
      |> Map.get(queue, [])
      |> ordered()
      |> Enum.take(count)
      |> Enum.map(&public/1)

    {:reply, entries, state}
  end

  def handle_call({:drain, queue, handler, count}, _from, state) do
    entries = Map.get(state.queues, queue, [])
    to_visit = entries |> ordered() |> Enum.take(count)

    {outcomes, stats} =
      Enum.reduce(to_visit, {%{}, %{succeeded: 0, failed: 0, processed: []}}, fn entry,
                                                                                 {out, acc} ->
        acc = %{acc | processed: acc.processed ++ [entry.id]}

        case run_handler(handler, entry.message) do
          :success ->
            {Map.put(out, entry.id, :remove), %{acc | succeeded: acc.succeeded + 1}}

          {:failure, _reason} ->
            {Map.put(out, entry.id, {:keep, entry.retry_count + 1}),
             %{acc | failed: acc.failed + 1}}
        end
      end)

    new_entries =
      entries
      |> Enum.reduce([], fn e, acc ->
        case Map.get(outcomes, e.id) do
          :remove -> acc
          {:keep, rc} -> [%{e | retry_count: rc} | acc]
          nil -> [e | acc]
        end
      end)
      |> Enum.reverse()

    {:reply, {:ok, stats}, put_queue(state, queue, new_entries)}
  end

  def handle_call({:purge, queue, older_than}, _from, state) do
    entries = Map.get(state.queues, queue, [])
    now = state.clock.()
    {kept, purged} = Enum.split_with(entries, fn e -> now - e.pushed_at < older_than end)
    {:reply, {:ok, length(purged)}, put_queue(state, queue, kept)}
  end

  ## Helpers

  defp full?(:infinity, _len), do: false
  defp full?(cap, len) when is_integer(cap), do: len >= cap

  # highest priority first, then FIFO (ascending id = insertion order)
  defp ordered(entries) do
    Enum.sort_by(entries, fn e -> {-Map.fetch!(@rank, e.priority), e.id} end)
  end

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
    Map.take(e, [:id, :message, :error_reason, :metadata, :priority, :retry_count])
  end
end
```
