# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `processed` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir GenServer module called `CancellablePriorityQueue` that processes tasks based on numeric priority levels and supports cancelling pending tasks by reference.

I need these functions in the public API:

- `CancellablePriorityQueue.start_link(opts)` to start the process. It should accept a `:name` option for process registration and a `:processor` option which is a single-arity function that will be called to "process" each task. If not provided, default to `fn task -> task end` (identity). The GenServer should process tasks one at a time asynchronously — after finishing one task, it immediately picks the next highest-priority one if any are queued.

- `CancellablePriorityQueue.enqueue(server, task, priority)` where priority is a non-negative integer (lower number = higher priority, like Unix nice values). Priority `0` is the highest. This adds a task to the queue and triggers processing if the processor is currently idle. Return `{:ok, ref}` where `ref` is a unique reference (use `make_ref()`) that can be used to cancel the task later.

- `CancellablePriorityQueue.cancel(server, ref)` which attempts to cancel a pending (not-yet-started) task identified by `ref`. Returns `:ok` if the task was found and removed from the queue, or `{:error, :not_found}` if the ref doesn't match any pending task (either it was already processed, already cancelled, or never existed). You cannot cancel a task that is currently being processed; such a call also returns `{:error, :not_found}`.

- `CancellablePriorityQueue.status(server)` returning a map with the total pending count, a breakdown of pending counts per priority level, and the count of cancelled tasks. For example: `%{pending: 5, by_priority: %{0 => 2, 1 => 1, 5 => 2}, cancelled: 3}`. Only include priority levels that have pending tasks in the `by_priority` map (so an empty queue reports `by_priority: %{}`).

- `CancellablePriorityQueue.drain(server)` which blocks until all currently enqueued tasks have been processed and the queue is empty. This is essential for testing. Return `:ok`.

- `CancellablePriorityQueue.processed(server)` which returns a list of `{task, result}` tuples in the order tasks were processed.

- `CancellablePriorityQueue.peek(server)` which returns `{:ok, task, priority}` for the next task that would be processed (the highest-priority task at the front of its queue), without removing it. Returns `:empty` if the queue is empty.

The priority ordering is numeric: `0` is highest priority, then `1`, then `2`, etc. The GenServer must always pick the lowest-numbered priority task available next. Within the same priority level, tasks must be processed in FIFO order (the order they were enqueued).

Internally, use a map of `priority_number => :queue.new()` to store tasks, creating new queue entries dynamically as new priority levels are seen. Each queue entry should be `{ref, task}` so tasks can be identified for cancellation.

Processing should happen via internal message passing — when a task is enqueued and the processor is idle, the GenServer sends itself a `:process_next` message. When a task finishes processing, if more tasks remain, it sends itself another `:process_next` message. The processor function is called synchronously inside a spawned process from `handle_info` for `:process_next`.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## The module with `processed` missing

```elixir
defmodule CancellablePriorityQueue do
  @moduledoc """
  A GenServer that processes tasks based on numeric priority levels (lower = higher priority)
  with support for cancelling pending tasks by reference.
  """

  use GenServer

  @type server :: GenServer.server()

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {processor, opts} = Keyword.pop(opts, :processor, fn task -> task end)
    {name, _opts} = Keyword.pop(opts, :name)

    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, %{processor: processor}, gen_opts)
  end

  @doc "Enqueues `task` at numeric `priority` (lower = higher). Returns `{:ok, ref}`."
  @spec enqueue(server(), term(), non_neg_integer()) :: {:ok, reference()}
  def enqueue(server, task, priority) when is_integer(priority) and priority >= 0 do
    GenServer.call(server, {:enqueue, task, priority})
  end

  @spec cancel(server(), reference()) :: :ok | {:error, :not_found}
  def cancel(server, ref) when is_reference(ref) do
    GenServer.call(server, {:cancel, ref})
  end

  @spec status(server()) :: %{
          pending: non_neg_integer(),
          by_priority: %{non_neg_integer() => non_neg_integer()},
          cancelled: non_neg_integer()
        }
  def status(server) do
    GenServer.call(server, :status)
  end

  @spec peek(server()) :: {:ok, term(), non_neg_integer()} | :empty
  def peek(server) do
    GenServer.call(server, :peek)
  end

  def processed(server) do
    # TODO
  end

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
      queues: %{},
      processor: processor,
      processing: false,
      current_task: nil,
      current_ref: nil,
      processed: [],
      cancelled_count: 0,
      drain_waiters: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:enqueue, task, priority}, _from, state) do
    ref = make_ref()
    entry = {ref, task}

    queue = Map.get(state.queues, priority, :queue.new())
    updated_queue = :queue.in(entry, queue)
    queues = Map.put(state.queues, priority, updated_queue)

    state =
      %{state | queues: queues}
      |> maybe_trigger_processing()

    {:reply, {:ok, ref}, state}
  end

  def handle_call({:cancel, ref}, _from, state) do
    case find_and_remove(state.queues, ref) do
      {:found, updated_queues} ->
        queues = clean_empty_queues(updated_queues)
        state = %{state | queues: queues, cancelled_count: state.cancelled_count + 1}
        {:reply, :ok, state}

      :not_found ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:status, _from, state) do
    by_priority =
      state.queues
      |> Enum.map(fn {priority, queue} -> {priority, :queue.len(queue)} end)
      |> Enum.filter(fn {_p, count} -> count > 0 end)
      |> Map.new()

    pending = Enum.reduce(by_priority, 0, fn {_p, count}, acc -> acc + count end)

    result = %{
      pending: pending,
      by_priority: by_priority,
      cancelled: state.cancelled_count
    }

    {:reply, result, state}
  end

  def handle_call(:peek, _from, state) do
    case peek_highest(state.queues) do
      nil ->
        {:reply, :empty, state}

      {task, priority} ->
        {:reply, {:ok, task, priority}, state}
    end
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

      {{_ref, task}, queues} ->
        queues = clean_empty_queues(queues)
        parent = self()
        processor = state.processor

        {pid, mon_ref} =
          spawn_monitor(fn ->
            result = processor.(task)
            send(parent, {:task_result, self(), result})
          end)

        new_state = %{
          state
          | queues: queues,
            current_task: task,
            current_ref: {pid, mon_ref}
        }

        {:noreply, new_state}
    end
  end

  def handle_info({:task_result, pid, result}, %{current_ref: {pid, _ref}} = state) do
    state = %{state | processed: [{state.current_task, result} | state.processed]}
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, pid, _}, %{current_ref: {pid, ref}} = state) do
    state = %{state | current_task: nil, current_ref: nil}

    if queue_empty?(state) do
      state = %{state | processing: false} |> notify_drain_waiters()
      {:noreply, state}
    else
      send(self(), :process_next)
      {:noreply, state}
    end
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
    case sorted_priorities(queues) do
      [] ->
        {nil, queues}

      [priority | _rest] ->
        case :queue.out(queues[priority]) do
          {{:value, entry}, rest} ->
            {entry, Map.put(queues, priority, rest)}

          {:empty, _} ->
            {nil, queues}
        end
    end
  end

  defp peek_highest(queues) do
    case sorted_priorities(queues) do
      [] ->
        nil

      [priority | _rest] ->
        case :queue.peek(queues[priority]) do
          {:value, {_ref, task}} -> {task, priority}
          :empty -> nil
        end
    end
  end

  defp sorted_priorities(queues) do
    queues
    |> Map.keys()
    |> Enum.filter(fn p -> not :queue.is_empty(queues[p]) end)
    |> Enum.sort()
  end

  defp find_and_remove(queues, target_ref) do
    Enum.reduce_while(queues, :not_found, fn {priority, queue}, _acc ->
      items = :queue.to_list(queue)

      case Enum.split_with(items, fn {ref, _task} -> ref != target_ref end) do
        {remaining, [{^target_ref, _task}]} ->
          new_queue = :queue.from_list(remaining)
          updated_queues = Map.put(queues, priority, new_queue)
          {:halt, {:found, updated_queues}}

        {_all_items, []} ->
          {:cont, :not_found}
      end
    end)
  end

  defp clean_empty_queues(queues) do
    queues
    |> Enum.reject(fn {_priority, queue} -> :queue.is_empty(queue) end)
    |> Map.new()
  end

  defp queue_empty?(state) do
    Enum.all?(state.queues, fn {_p, queue} -> :queue.is_empty(queue) end)
  end

  defp notify_drain_waiters(%{drain_waiters: []} = state), do: state

  defp notify_drain_waiters(state) do
    Enum.each(state.drain_waiters, &GenServer.reply(&1, :ok))
    %{state | drain_waiters: []}
  end
end
```

Give me only the complete implementation of `processed` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
