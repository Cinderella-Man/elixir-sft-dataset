# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `processed`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

Write me an Elixir GenServer module called `ConcurrentPriorityQueue` that processes tasks based on priority levels with configurable concurrency — up to N tasks can be processed simultaneously.

I need these functions in the public API:

- `ConcurrentPriorityQueue.start_link(opts)` to start the process. It should accept:
  - `:name` — option for process registration
  - `:processor` — a single-arity function called to "process" each task. Default: `fn task -> task end`
  - `:max_concurrency` — the maximum number of tasks that can be processed simultaneously (default `1`). Must be a positive integer, and `start_link/1` must validate it: a non-positive or non-integer value raises an `ArgumentError` (it must not return an error tuple or exit).

  When a task finishes and there are more tasks queued, the GenServer immediately picks the next highest-priority task if a concurrency slot is available.

- `ConcurrentPriorityQueue.enqueue(server, task, priority)` where priority is one of `:critical`, `:normal`, or `:low`. This adds a task to the queue and triggers processing if there is an available concurrency slot. Return `:ok`.

- `ConcurrentPriorityQueue.status(server)` returning a map with exactly the keys `:critical`, `:normal`, `:low`, `:active`, and `:max_concurrency` — the pending task counts per priority level, the number of currently active (in-progress) tasks, and the max concurrency setting. Example: `%{critical: 0, normal: 2, low: 1, active: 3, max_concurrency: 5}`. Pending counts should only include tasks that have not yet started processing.

- `ConcurrentPriorityQueue.drain(server)` which blocks until all currently enqueued tasks have been processed and the queue is empty and no tasks are actively being processed. Return `:ok`. Calling `drain/1` on an already-empty, idle queue must return `:ok` immediately.

- `ConcurrentPriorityQueue.processed(server)` which returns a list of `{task, result}` tuples in the order tasks finished processing (an empty list when nothing has been processed). Note: with concurrency > 1, the completion order may differ from the start order.

The priority ordering is `:critical` > `:normal` > `:low`. The GenServer must always pick the highest priority task available next when a slot opens up. Within the same priority level, tasks must be started in FIFO order (the order they were enqueued).

Each task's `:processor` function must run inside its own separate spawned process (one process per task), and that process must terminate once the task's processing completes. The number of these worker processes running at once must never exceed `:max_concurrency`. The GenServer records the `{task, result}` pair once a task finishes, where `result` is the value the processor returned — including when the processor returns `nil` (that is still recorded as `{task, nil}`).

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## The module with `processed` missing

```elixir
defmodule ConcurrentPriorityQueue do
  @moduledoc """
  A GenServer that processes tasks based on priority levels (`:critical` > `:normal` > `:low`)
  with configurable concurrency.

  Up to `:max_concurrency` tasks can be processed simultaneously. Within a priority level tasks
  are started in FIFO order. Each task is run by a spawned, monitored worker process which sends
  its result back to the server before exiting; the server records `{task, result}` pairs in
  completion order.
  """

  use GenServer

  @type priority :: :critical | :normal | :low
  @type server :: GenServer.server()

  @priority_order [:critical, :normal, :low]

  # Unique marker used to distinguish "no result was reported" from a legitimate `nil` result.
  @no_result :"$concurrent_priority_queue_no_result"

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the queue process.

  Options:

    * `:name` — optional name for process registration
    * `:processor` — single-arity function invoked for each task (default: `fn task -> task end`)
    * `:max_concurrency` — positive integer, maximum simultaneous tasks (default: `1`)

  Raises `ArgumentError` when `:max_concurrency` is not a positive integer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {processor, opts} = Keyword.pop(opts, :processor, fn task -> task end)
    {max_concurrency, opts} = Keyword.pop(opts, :max_concurrency, 1)
    {name, _opts} = Keyword.pop(opts, :name)

    if not (is_integer(max_concurrency) and max_concurrency > 0) do
      raise ArgumentError, ":max_concurrency must be a positive integer"
    end

    gen_opts = if name, do: [name: name], else: []

    GenServer.start_link(
      __MODULE__,
      %{processor: processor, max_concurrency: max_concurrency},
      gen_opts
    )
  end

  @doc "Enqueues `task` at `priority` for concurrent processing. Returns `:ok`."
  @spec enqueue(server(), term(), priority()) :: :ok
  def enqueue(server, task, priority) when priority in @priority_order do
    GenServer.call(server, {:enqueue, task, priority})
  end

  @doc """
  Returns a map with the pending count per priority level, the number of active tasks and the
  configured max concurrency.
  """
  @spec status(server()) :: %{
          critical: non_neg_integer(),
          normal: non_neg_integer(),
          low: non_neg_integer(),
          active: non_neg_integer(),
          max_concurrency: pos_integer()
        }
  def status(server) do
    GenServer.call(server, :status)
  end

  def processed(server) do
    # TODO
  end

  @doc "Blocks until the queue is empty and no tasks are actively being processed."
  @spec drain(server()) :: :ok
  def drain(server) do
    GenServer.call(server, :drain, :infinity)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(%{processor: processor, max_concurrency: max_concurrency}) do
    state = %{
      queues: %{critical: :queue.new(), normal: :queue.new(), low: :queue.new()},
      processor: processor,
      max_concurrency: max_concurrency,
      # Map of pid => {task, monitor_ref}
      active_workers: %{},
      # Map of pid => result (received before :DOWN)
      pending_results: %{},
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
      critical: :queue.len(state.queues.critical),
      normal: :queue.len(state.queues.normal),
      low: :queue.len(state.queues.low),
      active: map_size(state.active_workers),
      max_concurrency: state.max_concurrency
    }

    {:reply, counts, state}
  end

  def handle_call(:processed, _from, state) do
    {:reply, Enum.reverse(state.processed), state}
  end

  def handle_call(:drain, from, state) do
    if queue_empty?(state) and map_size(state.active_workers) == 0 do
      {:reply, :ok, state}
    else
      {:noreply, %{state | drain_waiters: [from | state.drain_waiters]}}
    end
  end

  @impl true
  def handle_info(:process_next, state) do
    if map_size(state.active_workers) >= state.max_concurrency do
      # All slots full — processing is re-triggered when a worker finishes.
      {:noreply, state}
    else
      case pop_highest(state.queues) do
        {nil, _queues} ->
          {:noreply, maybe_notify_drain(state)}

        {task, queues} ->
          parent = self()
          processor = state.processor

          {pid, ref} =
            spawn_monitor(fn ->
              result = processor.(task)
              send(parent, {:task_result, self(), result})
            end)

          active_workers = Map.put(state.active_workers, pid, {task, ref})

          new_state =
            %{state | queues: queues, active_workers: active_workers}
            |> maybe_trigger_processing()

          {:noreply, new_state}
      end
    end
  end

  def handle_info({:task_result, pid, result}, state) do
    if Map.has_key?(state.active_workers, pid) do
      # Store the result; it is finalized when the worker's :DOWN arrives.
      {:noreply, %{state | pending_results: Map.put(state.pending_results, pid, result)}}
    else
      {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    case Map.pop(state.active_workers, pid) do
      {{task, ^ref}, remaining_workers} ->
        {result, pending_results} = Map.pop(state.pending_results, pid, @no_result)

        processed =
          case result do
            @no_result -> state.processed
            value -> [{task, value} | state.processed]
          end

        state =
          %{
            state
            | active_workers: remaining_workers,
              pending_results: pending_results,
              processed: processed
          }
          |> maybe_trigger_processing()
          |> maybe_notify_drain()

        {:noreply, state}

      {_other, _workers} ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp maybe_trigger_processing(state) do
    available_slots = state.max_concurrency - map_size(state.active_workers)

    if available_slots > 0 and not queue_empty?(state) do
      send(self(), :process_next)
    end

    state
  end

  defp pop_highest(queues) do
    Enum.find_value(@priority_order, {nil, queues}, fn priority ->
      case :queue.out(queues[priority]) do
        {{:value, task}, rest} -> {task, Map.put(queues, priority, rest)}
        {:empty, _} -> nil
      end
    end)
  end

  defp queue_empty?(state) do
    Enum.all?(@priority_order, fn p -> :queue.is_empty(state.queues[p]) end)
  end

  defp maybe_notify_drain(state) do
    if queue_empty?(state) and map_size(state.active_workers) == 0 do
      notify_drain_waiters(state)
    else
      state
    end
  end

  defp notify_drain_waiters(%{drain_waiters: []} = state), do: state

  defp notify_drain_waiters(state) do
    Enum.each(state.drain_waiters, &GenServer.reply(&1, :ok))
    %{state | drain_waiters: []}
  end
end
```

Output only `processed` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
