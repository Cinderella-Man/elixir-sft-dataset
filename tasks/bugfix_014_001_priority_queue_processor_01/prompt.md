# Debug and repair this module

A colleague shipped the module below for the task described next, and one
behavior bug made it through review. The test suite (not shown here)
produces the failure report at the bottom. Track the bug down and repair
it — keep the diff minimal and leave working code exactly as it is. Reply
with the complete corrected module.

## What the module is supposed to do

# Design Brief: `PriorityQueue` — a priority-ordered task processor

## Problem

We need an Elixir GenServer module called `PriorityQueue` that processes tasks based on priority levels, always picking the highest priority task available. Tasks are processed one at a time asynchronously — after finishing one task, the process immediately picks the next highest-priority one if any are queued.

## Constraints

- Use only OTP standard library, no external dependencies.
- The priority ordering is `:high` > `:normal` > `:low`. The GenServer must always pick the highest priority task available next.
- Within the same priority level, tasks must be processed in FIFO order (the order they were enqueued).
- Processing must happen via internal message passing:
  - When a task is enqueued and the processor is idle, the GenServer sends itself a `:process_next` message.
  - When a task finishes processing, if more tasks remain, it sends itself another `:process_next` message.
  - The `handle_info` for `:process_next` dequeues the highest-priority task and runs the processor function in a separate spawned, monitored process (e.g. via `spawn_monitor/1`) — never inline in the GenServer loop — so that `enqueue`, `status`, and `drain` calls remain responsive even while a long-running or blocking task is being processed. When the spawned process finishes, the GenServer records the result and moves on.
- Each processed task's result must be stored internally so tests can retrieve the processing history.
- Deliver the complete module in a single file.

## Required interface

1. `PriorityQueue.start_link(opts)` — starts the process. It should accept a `:name` option for process registration and a `:processor` option which is a single-arity function that will be called to "process" each task. If not provided, `:processor` defaults to `fn task -> task end` (identity).

2. `PriorityQueue.enqueue(server, task, priority)` — where `priority` is one of `:high`, `:normal`, or `:low`. This adds a task to the queue and triggers processing if the processor is currently idle. Returns `:ok`.

3. `PriorityQueue.status(server)` — returns a map of pending task counts per priority level, like `%{high: 0, normal: 2, low: 1}`. This count should only include tasks that have not yet started processing.

4. `PriorityQueue.drain(server)` — blocks until all currently enqueued tasks have been processed and the queue is empty. This is essential for testing. Returns `:ok`. On an already-empty, idle queue it returns `:ok` immediately.

5. `PriorityQueue.processed(server)` — returns a list of `{task, result}` tuples in the order tasks were processed, and `[]` before anything has been processed.

## Acceptance criteria

- The module is named `PriorityQueue` and is a GenServer.
- The highest priority task available is always processed next, with `:high` > `:normal` > `:low`, and ties within a level broken in FIFO order.
- Tasks are processed one at a time, asynchronously, each in a spawned, monitored process — never inline in the GenServer loop — so `enqueue`, `status`, and `drain` stay responsive during a long-running or blocking task.
- Processing is driven by `:process_next` messages the GenServer sends to itself: on enqueue-while-idle, and after each task finishes when tasks remain.
- `enqueue/3` returns `:ok`; `status/1` reflects only not-yet-started tasks; `drain/1` returns `:ok` (immediately on an empty, idle queue); `processed/1` returns `{task, result}` tuples in processing order, or `[]` before anything has been processed.
- Uses only the OTP standard library, delivered as one complete single-file module.

## The buggy module

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

    {:error, state}
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

## Failing test report

```
16 of 16 test(s) failed:

  * test processes a single enqueued task
      no match of right hand side value:
      
          {:error,
           %{
             processor: #Function<0.74310577/1 in PriorityQueueTest.recording_processor/0>,
             processed: [],
             queues: %{normal: {[], []}, high: {[], []}, low: {[], []}},
             processing: false,
             current_task: nil,
             current_ref: nil,
             drain_waiters: []
           }}
      

  * test processes multiple tasks of the same priority in FIFO order
      no match of right hand side value:
      
          {:error,
           %{
             processor: #Function<0.74310577/1 in PriorityQueueTest.recording_processor/0>,
             processed: [],
             queues: %{normal: {[], []}, high: {[], []}, low: {[], []}},
             processing: false,
             current_task: nil,
             current_ref: nil,
             drain_waiters: []
           }}
      

  * test high priority tasks are processed before normal and low
      no match of right hand side value:
      
          {:error,
           %{
             processor: #Function<0.74310577/1 in PriorityQueueTest.recording_processor/0>,
             processed: [],
             queues: %{normal: {[], []}, high: {[], []}, low: {[], []}},
             processing: false,
             current_task: nil,
             current_ref: nil,
             drain_waiters: []
           }}
      

  * test high beats normal beats low in a clean queue
      no match of right hand side value:
      
          {:error,
           %{
             processor: #Function<0.74310577/1 in PriorityQueueTest.recording_processor/0>,
             processed: [],
             queues: %{normal: {[], []}, high: {[], []}, low: {[], []}},
             processing: false,
             current_task: nil,
             current_ref: nil,
             drain_waiters: []
           }}
      

  (…12 more)
```
