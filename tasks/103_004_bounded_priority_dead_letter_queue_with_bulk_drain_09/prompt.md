# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `handle_call` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

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

## The module with `handle_call` missing

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

  @doc """
  Pushes a dead-lettered `message` (with its `error_reason`, `metadata`, and `priority`)
  onto `queue_name`. Drops the lowest-priority entry when the bounded queue is full.
  """
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

  def handle_call({:push, queue, message, error_reason, metadata, priority}, _from, state) do
    # TODO
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

Give me only the complete implementation of `handle_call` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
