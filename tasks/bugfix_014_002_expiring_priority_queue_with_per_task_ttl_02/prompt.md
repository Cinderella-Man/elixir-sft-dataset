# Debug and repair this module

A colleague shipped the module below for the task described next, and one
behavior bug made it through review. The test suite (not shown here)
produces the failure report at the bottom. Track the bug down and repair
it — keep the diff minimal and leave working code exactly as it is. Reply
with the complete corrected module.

## What the module is supposed to do

# Design Brief: `ExpiringPriorityQueue`

## Problem & Context

We need an Elixir GenServer module called `ExpiringPriorityQueue` that processes tasks based on priority levels, but also supports per-task TTL (time-to-live) so that stale tasks are skipped rather than processed.

## Constraints

- Deliver the complete module in a single file.
- Use only OTP standard library, no external dependencies.
- The GenServer must process tasks one at a time asynchronously — after finishing one task, it immediately picks the next highest-priority non-expired one if any are queued.
- While a task is being processed the server must stay responsive to `enqueue`, `status`, `processed`, `expired` and `drain` calls.
- The priority ordering is `:high` > `:normal` > `:low`. The GenServer must always pick the highest priority task available next. Within the same priority level, tasks must be processed in FIFO order (the order they were enqueued).
- Processing must happen via internal message passing — when a task is enqueued and the processor is idle, the GenServer sends itself a `:process_next` message. When a task finishes processing, if more tasks remain, it sends itself another `:process_next` message. The processor function is called synchronously inside a spawned process from `handle_info` for `:process_next`, so the GenServer's own loop is never blocked while a task runs.
- When the GenServer picks the next task to process via `:process_next`, it should check the task's expiration time against the current time. A task counts as expired the instant the current time reaches or passes its expiration time (`now >= expires_at`) — so a task whose expiry equals the current clock is treated as expired, not pending, and a task enqueued with `ttl_ms: 0` expires immediately. If the task has expired, it should be added to the expired list, skipped, and the GenServer should immediately try the next task. This means a single `:process_next` might skip multiple expired tasks before finding a valid one (or finding the queue empty).
- Use the configured `:clock` function for all TTL calculations to make testing deterministic.

## Required Interface

The public API must expose exactly these functions:

1. `ExpiringPriorityQueue.start_link(opts)` to start the process. It should accept a `:name` option for process registration and a `:processor` option which is a single-arity function that will be called to "process" each task. If not provided, default to `fn task -> task end` (identity). It should also accept `:default_ttl_ms` (default `5000`) which is the TTL applied to tasks that don't specify their own. It should accept a `:clock` option — a zero-arity function returning the current time in milliseconds (default `fn -> System.monotonic_time(:millisecond) end`).

2. `ExpiringPriorityQueue.enqueue(server, task, priority, opts \\ [])` where priority is one of `:high`, `:normal`, or `:low`. Guard this argument so that any other value (including a non-atom such as `"high"`) raises a `FunctionClauseError` from `enqueue` itself before the server is touched. Accepts an optional `:ttl_ms` in opts to override the default TTL for this specific task. The TTL countdown starts from the moment of enqueue, so a task enqueued when the clock reads `t` with an effective TTL of `ttl` expires at `t + ttl`. This adds a task to the queue and triggers processing if the processor is currently idle. Return `:ok`.

3. `ExpiringPriorityQueue.status(server)` returning a map with pending task counts per priority level and the count of expired tasks, exactly like `%{high: 0, normal: 2, low: 1, expired: 3}` (those four keys and no others). Pending counts should only include non-expired tasks that have not yet started processing; a task counts as pending only while the current time is strictly before its expiration (`now < expires_at`). The `expired` value is the total number of tasks recorded as expired so far.

4. `ExpiringPriorityQueue.drain(server)` which blocks until all currently enqueued tasks have been processed (or expired) and the queue is empty. On an already-idle, empty queue it returns immediately. This is essential for testing. Return `:ok`.

5. `ExpiringPriorityQueue.processed(server)` which returns a list of `{task, result}` tuples — where `result` is the value the processor function returned for that task — in the order tasks were processed (only successfully processed tasks, not expired ones).

6. `ExpiringPriorityQueue.expired(server)` which returns a list of `{task, priority}` tuples for tasks that were skipped due to expiration, in the order they were discovered as expired.

## Acceptance Criteria

- The GenServer processes tasks one at a time asynchronously, immediately picking the next highest-priority non-expired task after finishing one, and remains responsive to `enqueue`, `status`, `processed`, `expired`, and `drain` while a task is being processed.
- `start_link/1` honors `:name`, `:processor` (defaulting to `fn task -> task end`), `:default_ttl_ms` (defaulting to `5000`), and `:clock` (defaulting to `fn -> System.monotonic_time(:millisecond) end`), using that clock for all TTL calculations.
- `enqueue/4` guards `priority` to `:high`, `:normal`, or `:low`, raising `FunctionClauseError` from `enqueue` itself (before touching the server) on any other value including a non-atom such as `"high"`; honors `:ttl_ms` overriding `:default_ttl_ms`; sets expiration to `t + ttl` from the enqueue-time clock reading `t`; triggers processing when idle; and returns `:ok`.
- `status/1` returns a map with exactly the keys `high`, `normal`, `low`, and `expired`, e.g. `%{high: 0, normal: 2, low: 1, expired: 3}`, counting a task as pending only while `now < expires_at` and reporting the total number of expired tasks so far.
- `drain/1` blocks until the queue is empty (all tasks processed or expired), returns immediately on an already-idle empty queue, and returns `:ok`.
- `processed/1` returns `{task, result}` tuples for successfully processed tasks only, in processing order, with `result` being the processor's return value.
- `expired/1` returns `{task, priority}` tuples for tasks skipped due to expiration, in the order they were discovered as expired.
- Task selection always picks the highest priority available (`:high` > `:normal` > `:low`), FIFO within the same priority.
- A task is expired the instant `now >= expires_at` (equal-to-clock and `ttl_ms: 0` expire immediately); expired tasks are recorded, skipped, and the next task is tried immediately, so one `:process_next` may skip multiple expired tasks before finding a valid one or an empty queue.
- Processing uses internal `:process_next` message passing: enqueue-while-idle sends `:process_next`; task completion with remaining tasks sends another `:process_next`; the processor runs synchronously inside a process spawned from `handle_info` for `:process_next` so the GenServer loop is never blocked.
- The deliverable is the complete module in a single file using only the OTP standard library with no external dependencies.

## The buggy module

```elixir
defmodule ExpiringPriorityQueue do
  @moduledoc """
  A GenServer that processes tasks based on priority levels (:high > :normal > :low),
  with per-task TTL support. Tasks that expire before being picked up are skipped
  and recorded in an expired list.
  """

  use GenServer

  @type priority :: :high | :normal | :low
  @type server :: GenServer.server()

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {processor, opts} = Keyword.pop(opts, :processor, fn task -> task end)
    {default_ttl_ms, opts} = Keyword.pop(opts, :default_ttl_ms, 5000)
    {clock, opts} = Keyword.pop(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    {name, _opts} = Keyword.pop(opts, :name)

    gen_opts = if name, do: [name: name], else: []

    GenServer.start_link(
      __MODULE__,
      %{processor: processor, default_ttl_ms: default_ttl_ms, clock: clock},
      gen_opts
    )
  end

  @doc "Enqueues `task` at `priority` with a per-task TTL from `opts`. Returns `:ok`."
  @spec enqueue(server(), term(), priority(), keyword()) :: :ok
  def enqueue(server, task, priority, opts \\ []) when priority in [:high, :normal, :low] do
    GenServer.call(server, {:enqueue, task, priority, opts})
  end

  @spec status(server()) :: %{
          high: non_neg_integer(),
          normal: non_neg_integer(),
          low: non_neg_integer(),
          expired: non_neg_integer()
        }
  def status(server) do
    GenServer.call(server, :status)
  end

  @spec processed(server()) :: [{term(), term()}]
  def processed(server) do
    GenServer.call(server, :processed)
  end

  @spec expired(server()) :: [{term(), priority()}]
  def expired(server) do
    GenServer.call(server, :expired)
  end

  @spec drain(server()) :: :ok
  def drain(server) do
    GenServer.call(server, :drain, :infinity)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(%{processor: processor, default_ttl_ms: default_ttl_ms, clock: clock}) do
    state = %{
      queues: %{high: :queue.new(), normal: :queue.new(), low: :queue.new()},
      processor: processor,
      default_ttl_ms: default_ttl_ms,
      clock: clock,
      processing: false,
      current_task: nil,
      current_ref: nil,
      processed: [],
      expired: [],
      drain_waiters: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:enqueue, task, priority, opts}, _from, state) do
    ttl_ms = Keyword.get(opts, :ttl_ms, state.default_ttl_ms)
    now = state.clock.()
    expires_at = now + ttl_ms

    entry = {task, expires_at}
    updated_queue = :queue.in(entry, state.queues[priority])
    queues = Map.put(state.queues, priority, updated_queue)

    state =
      %{state | queues: queues}
      |> maybe_trigger_processing()

    {:reply, :ok, state}
  end

  def handle_call(:status, _from, state) do
    now = state.clock.()

    counts =
      Enum.reduce([:high, :normal, :low], %{}, fn priority, acc ->
        count =
          state.queues[priority]
          |> :queue.to_list()
          |> Enum.count(fn {_task, expires_at} -> expires_at > now end)

        Map.put(acc, priority, count)
      end)

    counts = Map.put(counts, :expired, length(state.expired))

    {:reply, counts, state}
  end

  def handle_call(:processed, _from, state) do
    {:reply, Enum.reverse(state.processed), state}
  end

  def handle_call(:expired, _from, state) do
    {:reply, Enum.reverse(state.expired), state}
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
    case pop_next_valid(state) do
      {:empty, state} ->
        state = %{state | processing: false} |> notify_drain_waiters()
        {:noreply, state}

      {:error, task, state} ->
        parent = self()
        processor = state.processor

        {pid, ref} =
          spawn_monitor(fn ->
            result = processor.(task)
            send(parent, {:task_result, self(), result})
          end)

        new_state = %{
          state
          | current_task: task,
            current_ref: {pid, ref}
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

  # Pops entries from the queues in priority order, skipping expired ones.
  # Returns {:ok, task, updated_state} or {:empty, updated_state}.
  defp pop_next_valid(state) do
    case pop_highest(state.queues) do
      {nil, _queues} ->
        {:empty, state}

      {{task, expires_at}, queues, priority} ->
        now = state.clock.()
        state = %{state | queues: queues}

        if expires_at <= now do
          # Task has expired — record it and try the next one
          state = %{state | expired: [{task, priority} | state.expired]}
          pop_next_valid(state)
        else
          {:ok, task, state}
        end
    end
  end

  defp pop_highest(queues) do
    Enum.find_value([:high, :normal, :low], {nil, queues}, fn priority ->
      case :queue.out(queues[priority]) do
        {{:value, entry}, rest} -> {entry, Map.put(queues, priority, rest), priority}
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
12 of 15 test(s) failed:

  * test processes a single enqueued task
      {:EXIT, #PID<0.207.0>}: {{:case_clause, {:ok, "task_a", %{processor: #Function<2.120629350/1 in ExpiringPriorityQueueTest.recording_processor/0>, expired: [], default_ttl_ms: 10000, clock: #Function<1.120629350/0 in ExpiringPriorityQueueTest.clock_fn/1>, processed: [], queues: %{normal: {[], []}, high: {[], []}, low: {[], []}}, processing: true, current_task: nil, current_ref: nil, drain_waiters: []}}}, [{ExpiringPriorityQueue, :handle_info, 2, [file: ~c".gen_staging/bugfix_014_002_expiring_prio

  * test processes multiple tasks of the same priority in FIFO order
      {:EXIT, #PID<0.210.0>}: {{:case_clause, {:ok, "first", %{processor: #Function<2.120629350/1 in ExpiringPriorityQueueTest.recording_processor/0>, expired: [], default_ttl_ms: 10000, clock: #Function<1.120629350/0 in ExpiringPriorityQueueTest.clock_fn/1>, processed: [], queues: %{normal: {[], []}, high: {[], []}, low: {[], []}}, processing: true, current_task: nil, current_ref: nil, drain_waiters: []}}}, [{ExpiringPriorityQueue, :handle_info, 2, [file: ~c".gen_staging/bugfix_014_002_expiring_prior

  * test high priority tasks are processed before normal and low
      {:EXIT, #PID<0.213.0>}: {{:case_clause, {:ok, "blocker", %{processor: #Function<17.120629350/1 in ExpiringPriorityQueueTest."test high priority tasks are processed before normal and low"/1>, expired: [], default_ttl_ms: 100000, clock: #Function<1.120629350/0 in ExpiringPriorityQueueTest.clock_fn/1>, processed: [], queues: %{normal: {[], []}, high: {[], []}, low: {[], []}}, processing: true, current_task: nil, current_ref: nil, drain_waiters: []}}}, [{ExpiringPriorityQueue, :handle_info, 2, [file

  * test expired tasks are skipped and recorded
      {:EXIT, #PID<0.217.0>}: {{:case_clause, {:ok, "blocker", %{processor: #Function<8.120629350/1 in ExpiringPriorityQueueTest."test expired tasks are skipped and recorded"/1>, expired: [], default_ttl_ms: 100, clock: #Function<1.120629350/0 in ExpiringPriorityQueueTest.clock_fn/1>, processed: [], queues: %{normal: {[], []}, high: {[], []}, low: {[], []}}, processing: true, current_task: nil, current_ref: nil, drain_waiters: []}}}, [{ExpiringPriorityQueue, :handle_info, 2, [file: ~c".gen_staging/bug

  (…8 more)
```
