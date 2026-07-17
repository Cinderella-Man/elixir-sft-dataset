# Implement `maybe_trigger_processing/1`

You are given the `PriorityQueue` GenServer module below, complete except for the
private helper `maybe_trigger_processing/1`. Implement it.

`maybe_trigger_processing/1` takes the current server `state` and decides whether to
kick off processing of the next task. It is called from `handle_call/3` right after a
task has been enqueued.

Its contract:

- If the processor is already busy (the state's `:processing` field is `true`), do
  nothing and return the state unchanged. A task is already in flight, and it will
  send itself a `:process_next` message when it finishes, so there is nothing to do.
- Otherwise the processor is idle. Check whether there are any pending tasks using the
  `queue_empty?/1` helper:
  - If every priority queue is empty, return the state unchanged (nothing to process).
  - If at least one task is queued, send the GenServer itself a `:process_next` message
    (via `send(self(), :process_next)`) and return the state with `:processing` set to
    `true`, marking the processor as busy so concurrent enqueues don't trigger a second
    processing loop.

The function must be idempotent with respect to an already-running processor: calling it
repeatedly while `:processing` is `true` must never enqueue extra `:process_next`
messages.

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

  defp maybe_trigger_processing(%{processing: true} = state) do
    # TODO
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