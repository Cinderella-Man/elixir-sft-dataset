# Rework this solution for a changed brief

The module below is a complete, tested solution to a neighboring task. Treat
it as your starting codebase, not as a suggestion — carry over what still
fits and rewrite what the new brief demands. Where old code and the new
specification conflict (module name, public API, behavior, constraints,
output format), the new specification is authoritative. Return the complete
final result.

## Existing code (your starting point)

```elixir
defmodule PriorityQueue do
  @moduledoc """
  A GenServer that processes tasks based on priority levels (:high > :normal > :low).

  Tasks within the same priority level are processed in FIFO order.
  Processing happens asynchronously one task at a time. The actual
  processor function runs in a spawned process so the GenServer remains
  responsive to enqueue/status/drain calls while a task is being worked on.

  After each task completes the GenServer re-schedules itself via an internal
  `:process_next` message. That message either picks the next highest-priority
  task or, when nothing remains, transitions the server back to the idle state
  so that a task enqueued later triggers processing again.
  """

  use GenServer

  @typedoc "Priority levels in descending order of urgency."
  @type priority :: :high | :normal | :low

  @typedoc "A GenServer name or pid."
  @type server :: GenServer.server()

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the PriorityQueue process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {processor, opts} = Keyword.pop(opts, :processor, fn task -> task end)
    {name, _opts} = Keyword.pop(opts, :name)

    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, %{processor: processor}, gen_opts)
  end

  @doc """
  Enqueues a task at the given priority (`:high`, `:normal`, or `:low`).
  """
  @spec enqueue(server(), term(), priority()) :: :ok
  def enqueue(server, task, priority) when priority in [:high, :normal, :low] do
    GenServer.call(server, {:enqueue, task, priority})
  end

  @doc """
  Returns a map of pending task counts per priority level.
  """
  @spec status(server()) :: %{
          high: non_neg_integer(),
          normal: non_neg_integer(),
          low: non_neg_integer()
        }
  def status(server) do
    GenServer.call(server, :status)
  end

  @doc """
  Returns the processing history as a list of `{task, result}` tuples.
  """
  @spec processed(server()) :: [{term(), term()}]
  def processed(server) do
    GenServer.call(server, :processed)
  end

  @doc """
  Blocks until the queue is empty and the processor is idle.
  """
  @spec drain(server()) :: :ok
  def drain(server) do
    GenServer.call(server, :drain, :infinity)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(%{processor: processor}) do
    state = %{
      queues: %{high: :queue.new(), normal: :queue.new(), low: :queue.new()},
      processor: processor,
      processing: false,
      current_task: nil,
      current_ref: nil,
      processed: [],
      drain_waiters: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:enqueue, task, priority}, _from, state) do
    updated_queue = :queue.in(task, state.queues[priority])
    queues = Map.put(state.queues, priority, updated_queue)

    state =
      %{state | queues: queues}
      |> maybe_trigger_processing()

    {:reply, :ok, state}
  end

  def handle_call(:status, _from, state) do
    counts = %{
      high: :queue.len(state.queues.high),
      normal: :queue.len(state.queues.normal),
      low: :queue.len(state.queues.low)
    }

    {:reply, counts, state}
  end

  def handle_call(:processed, _from, state) do
    {:reply, Enum.reverse(state.processed), state}
  end

  def handle_call(:drain, from, state) do
    if queue_empty?(state) and not state.processing do
      {:reply, :ok, state}
    else
      {:noreply, %{state | drain_waiters: [from | state.drain_waiters]}}
    end
  end

  @impl true
  def handle_info(:process_next, state) do
    case pop_highest(state.queues) do
      {nil, _queues} ->
        state = %{state | processing: false} |> notify_drain_waiters()
        {:noreply, state}

      {task, queues} ->
        parent = self()
        processor = state.processor

        {pid, ref} =
          spawn_monitor(fn ->
            result = processor.(task)
            send(parent, {:task_result, self(), result})
          end)

        new_state = %{
          state
          | queues: queues,
            current_task: task,
            current_ref: {pid, ref}
        }

        {:noreply, new_state}
    end
  end

  def handle_info({:task_result, pid, result}, %{current_ref: {pid, _ref}} = state) do
    state = %{state | processed: [{state.current_task, result} | state.processed]}
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, %{current_ref: {pid, ref}} = state) do
    state = %{state | current_task: nil, current_ref: nil}
    send(self(), :process_next)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp maybe_trigger_processing(%{processing: true} = state), do: state

  defp maybe_trigger_processing(state) do
    if queue_empty?(state) do
      state
    else
      send(self(), :process_next)
      %{state | processing: true}
    end
  end

  defp pop_highest(queues) do
    Enum.find_value([:high, :normal, :low], {nil, queues}, fn priority ->
      case :queue.out(queues[priority]) do
        {{:value, task}, rest} -> {task, Map.put(queues, priority, rest)}
        {:empty, _} -> nil
      end
    end)
  end

  defp queue_empty?(state) do
    Enum.all?([:high, :normal, :low], fn p -> :queue.is_empty(state.queues[p]) end)
  end

  defp notify_drain_waiters(%{drain_waiters: []} = state), do: state

  defp notify_drain_waiters(state) do
    Enum.each(state.drain_waiters, &GenServer.reply(&1, :ok))
    %{state | drain_waiters: []}
  end
end
```

## New specification

# Ticket: `CancellablePriorityQueue` — GenServer priority queue with cancellation

Implement an Elixir GenServer module named `CancellablePriorityQueue` that processes tasks by numeric priority level and supports cancelling pending tasks by reference. Deliver the complete module in a single file. Use only the OTP standard library — no external dependencies.

**Startup — `CancellablePriorityQueue.start_link(opts)`**
- Starts the process.
- Accepts a `:name` option for process registration.
- Accepts a `:processor` option: a single-arity function called to "process" each task; if not provided, default to `fn task -> task end` (identity).
- Processes tasks one at a time asynchronously — after finishing one task, immediately picks the next highest-priority one if any are queued.

**Enqueue — `CancellablePriorityQueue.enqueue(server, task, priority)`**
- `priority` is a non-negative integer; lower number = higher priority (like Unix nice values). Priority `0` is the highest.
- Adds a task to the queue and triggers processing if the processor is currently idle.
- Returns `{:ok, ref}` where `ref` is a unique reference (use `make_ref()`) usable to cancel the task later.

**Cancel — `CancellablePriorityQueue.cancel(server, ref)`**
- Attempts to cancel a pending (not-yet-started) task identified by `ref`.
- Returns `:ok` if the task was found and removed from the queue.
- Returns `{:error, :not_found}` if the ref doesn't match any pending task (already processed, already cancelled, or never existed).
- A task currently being processed cannot be cancelled; such a call also returns `{:error, :not_found}`.

**Status — `CancellablePriorityQueue.status(server)`**
- Returns a map with the total pending count, a breakdown of pending counts per priority level, and the count of cancelled tasks. Example: `%{pending: 5, by_priority: %{0 => 2, 1 => 1, 5 => 2}, cancelled: 3}`.
- Only include priority levels that have pending tasks in `by_priority`; an empty queue reports `by_priority: %{}`.

**Drain — `CancellablePriorityQueue.drain(server)`**
- Blocks until all currently enqueued tasks have been processed and the queue is empty. Essential for testing.
- Returns `:ok`.

**Processed — `CancellablePriorityQueue.processed(server)`**
- Returns a list of `{task, result}` tuples in the order tasks were processed.

**Peek — `CancellablePriorityQueue.peek(server)`**
- Returns `{:ok, task, priority}` for the next task that would be processed (the highest-priority task at the front of its queue), without removing it.
- Returns `:empty` if the queue is empty.

**Priority ordering**
- Numeric: `0` is highest, then `1`, then `2`, etc. Always pick the lowest-numbered priority task available next.
- Within the same priority level, process tasks in FIFO order (the order they were enqueued).

**Internal storage**
- Use a map of `priority_number => :queue.new()` to store tasks, creating new queue entries dynamically as new priority levels are seen.
- Each queue entry should be `{ref, task}` so tasks can be identified for cancellation.

**Processing mechanism**
- Use internal message passing: when a task is enqueued and the processor is idle, the GenServer sends itself a `:process_next` message.
- When a task finishes processing, if more tasks remain, it sends itself another `:process_next` message.
- The processor function is called synchronously inside a spawned process from `handle_info` for `:process_next`.
