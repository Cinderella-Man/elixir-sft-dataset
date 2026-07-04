# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule ConcurrentPriorityQueue do
  @moduledoc """
  A GenServer that processes tasks based on priority levels (:critical > :normal > :low)
  with configurable concurrency. Up to `:max_concurrency` tasks can be processed simultaneously.
  """

  use GenServer

  @type priority :: :critical | :normal | :low
  @type server :: GenServer.server()

  @priority_order [:critical, :normal, :low]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {processor, opts} = Keyword.pop(opts, :processor, fn task -> task end)
    {max_concurrency, opts} = Keyword.pop(opts, :max_concurrency, 1)
    {name, _opts} = Keyword.pop(opts, :name)

    unless is_integer(max_concurrency) and max_concurrency > 0 do
      raise ArgumentError, ":max_concurrency must be a positive integer"
    end

    gen_opts = if name, do: [name: name], else: []

    GenServer.start_link(
      __MODULE__,
      %{processor: processor, max_concurrency: max_concurrency},
      gen_opts
    )
  end

  @spec enqueue(server(), term(), priority()) :: :ok
  def enqueue(server, task, priority) when priority in @priority_order do
    GenServer.call(server, {:enqueue, task, priority})
  end

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

  @spec processed(server()) :: [{term(), term()}]
  def processed(server) do
    GenServer.call(server, :processed)
  end

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
      # All slots full, do nothing — will be re-triggered when a worker finishes
      {:noreply, state}
    else
      case pop_highest(state.queues) do
        {nil, _queues} ->
          # Nothing to process
          state = maybe_notify_drain(state)
          {:noreply, state}

        {task, queues} ->
          parent = self()
          processor = state.processor

          {pid, ref} =
            spawn_monitor(fn ->
              result = processor.(task)
              send(parent, {:task_result, self(), result})
            end)

          active_workers = Map.put(state.active_workers, pid, {task, ref})

          new_state = %{state | queues: queues, active_workers: active_workers}

          # Try to fill more slots if available
          new_state = maybe_trigger_processing(new_state)

          {:noreply, new_state}
      end
    end
  end

  def handle_info({:task_result, pid, result}, state) do
    if Map.has_key?(state.active_workers, pid) do
      # Store result, will be finalized on :DOWN
      state = %{state | pending_results: Map.put(state.pending_results, pid, result)}
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    case Map.pop(state.active_workers, pid) do
      {{task, ^ref}, remaining_workers} ->
        # Finalize the result
        {result, pending_results} = Map.pop(state.pending_results, pid)

        processed =
          if result != nil do
            [{task, result} | state.processed]
          else
            state.processed
          end

        state = %{
          state
          | active_workers: remaining_workers,
            pending_results: pending_results,
            processed: processed
        }

        # Try to start more work
        state = maybe_trigger_processing(state)
        state = maybe_notify_drain(state)

        {:noreply, state}

      {nil, _} ->
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

## Test harness — implement the `# TODO` test

```elixir
defmodule ConcurrentPriorityQueueTest do
  use ExUnit.Case, async: false

  defp recording_processor do
    fn task ->
      Process.sleep(5)
      {:processed, task}
    end
  end

  setup do
    {:ok, pid} =
      ConcurrentPriorityQueue.start_link(
        processor: recording_processor(),
        max_concurrency: 1
      )

    %{pq: pid}
  end

  # -------------------------------------------------------
  # Basic enqueue / process (concurrency=1)
  # -------------------------------------------------------

  test "processes a single enqueued task", %{pq: pq} do
    assert :ok = ConcurrentPriorityQueue.enqueue(pq, "task_a", :normal)
    assert :ok = ConcurrentPriorityQueue.drain(pq)

    assert [{"task_a", {:processed, "task_a"}}] = ConcurrentPriorityQueue.processed(pq)
  end

  test "processes multiple tasks of the same priority in FIFO order with concurrency=1", %{pq: pq} do
    ConcurrentPriorityQueue.enqueue(pq, "first", :normal)
    ConcurrentPriorityQueue.enqueue(pq, "second", :normal)
    ConcurrentPriorityQueue.enqueue(pq, "third", :normal)

    ConcurrentPriorityQueue.drain(pq)

    tasks = ConcurrentPriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))
    assert tasks == ["first", "second", "third"]
  end

  # -------------------------------------------------------
  # Priority ordering
  # -------------------------------------------------------

  test "critical > normal > low priority ordering", %{pq: _pq} do
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      ConcurrentPriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end,
        max_concurrency: 1
      )

    # Occupy the single slot
    ConcurrentPriorityQueue.enqueue(pq2, "blocker", :low)
    Process.sleep(10)

    # Queue up tasks in reverse priority order
    ConcurrentPriorityQueue.enqueue(pq2, "low_a", :low)
    ConcurrentPriorityQueue.enqueue(pq2, "normal_a", :normal)
    ConcurrentPriorityQueue.enqueue(pq2, "critical_a", :critical)
    ConcurrentPriorityQueue.enqueue(pq2, "normal_b", :normal)
    ConcurrentPriorityQueue.enqueue(pq2, "critical_b", :critical)

    Process.exit(gate, :kill)
    ConcurrentPriorityQueue.drain(pq2)

    tasks = ConcurrentPriorityQueue.processed(pq2) |> Enum.map(&elem(&1, 0))

    assert tasks == [
             "blocker",
             "critical_a",
             "critical_b",
             "normal_a",
             "normal_b",
             "low_a"
           ]
  end

  # -------------------------------------------------------
  # Concurrency > 1
  # -------------------------------------------------------

  test "processes multiple tasks concurrently up to max_concurrency" do
    # TODO
  end

  test "never exceeds max_concurrency even under burst enqueue" do
    {:ok, hwm_agent} = Agent.start_link(fn -> {0, 0} end)

    {:ok, pq} =
      ConcurrentPriorityQueue.start_link(
        processor: fn task ->
          Agent.update(hwm_agent, fn {c, m} -> {c + 1, max(m, c + 1)} end)
          Process.sleep(20)
          Agent.update(hwm_agent, fn {c, m} -> {c - 1, m} end)
          {:processed, task}
        end,
        max_concurrency: 5
      )

    # Burst enqueue 25 tasks from multiple processes
    1..25
    |> Enum.map(fn i ->
      Task.async(fn ->
        priority = Enum.at([:critical, :normal, :low], rem(i, 3))
        ConcurrentPriorityQueue.enqueue(pq, i, priority)
      end)
    end)
    |> Enum.each(&Task.await/1)

    ConcurrentPriorityQueue.drain(pq)

    {_current, high_water_mark} = Agent.get(hwm_agent, & &1)
    assert high_water_mark <= 5

    processed = ConcurrentPriorityQueue.processed(pq)
    assert length(processed) == 25

    Agent.stop(hwm_agent)
  end

  test "concurrency=1 behaves like a sequential queue" do
    {:ok, hwm_agent} = Agent.start_link(fn -> {0, 0} end)

    {:ok, pq} =
      ConcurrentPriorityQueue.start_link(
        processor: fn task ->
          Agent.update(hwm_agent, fn {c, m} -> {c + 1, max(m, c + 1)} end)
          Process.sleep(10)
          Agent.update(hwm_agent, fn {c, m} -> {c - 1, m} end)
          {:processed, task}
        end,
        max_concurrency: 1
      )

    for i <- 1..5 do
      ConcurrentPriorityQueue.enqueue(pq, i, :normal)
    end

    ConcurrentPriorityQueue.drain(pq)

    {_current, high_water_mark} = Agent.get(hwm_agent, & &1)
    assert high_water_mark == 1

    Agent.stop(hwm_agent)
  end

  # -------------------------------------------------------
  # Priority with concurrency > 1
  # -------------------------------------------------------

  test "with concurrency > 1, higher priority tasks still get slots first" do
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq} =
      ConcurrentPriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end,
        max_concurrency: 2
      )

    # Fill both slots with blockers
    ConcurrentPriorityQueue.enqueue(pq, "blocker_1", :low)
    ConcurrentPriorityQueue.enqueue(pq, "blocker_2", :low)
    Process.sleep(10)

    # Queue up mixed priorities
    ConcurrentPriorityQueue.enqueue(pq, "low_a", :low)
    ConcurrentPriorityQueue.enqueue(pq, "critical_a", :critical)
    ConcurrentPriorityQueue.enqueue(pq, "normal_a", :normal)

    status = ConcurrentPriorityQueue.status(pq)
    assert status.active == 2
    assert status.critical == 1
    assert status.normal == 1
    assert status.low == 1

    # Release all blockers
    Process.exit(gate, :kill)
    ConcurrentPriorityQueue.drain(pq)

    tasks = ConcurrentPriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))

    # Blockers finish first (in some order), then critical, normal, low
    # With concurrency=2, the two blockers finish ~simultaneously,
    # then critical_a and normal_a start together, then low_a
    blocker_tasks = Enum.take(tasks, 2) |> Enum.sort()
    assert blocker_tasks == ["blocker_1", "blocker_2"]

    remaining = Enum.drop(tasks, 2)
    # critical_a should appear before low_a in the remaining
    critical_idx = Enum.find_index(remaining, &(&1 == "critical_a"))
    low_idx = Enum.find_index(remaining, &(&1 == "low_a"))
    assert critical_idx < low_idx
  end

  # -------------------------------------------------------
  # Status reporting
  # -------------------------------------------------------

  test "status reports accurate counts", %{pq: _pq} do
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      ConcurrentPriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end,
        max_concurrency: 2
      )

    # Fill both slots
    ConcurrentPriorityQueue.enqueue(pq2, "active_1", :normal)
    ConcurrentPriorityQueue.enqueue(pq2, "active_2", :normal)
    Process.sleep(10)

    # Queue pending tasks
    ConcurrentPriorityQueue.enqueue(pq2, "c1", :critical)
    ConcurrentPriorityQueue.enqueue(pq2, "n1", :normal)
    ConcurrentPriorityQueue.enqueue(pq2, "l1", :low)
    ConcurrentPriorityQueue.enqueue(pq2, "l2", :low)

    status = ConcurrentPriorityQueue.status(pq2)
    assert status.critical == 1
    assert status.normal == 1
    assert status.low == 2
    assert status.active == 2
    assert status.max_concurrency == 2

    Process.exit(gate, :kill)
    ConcurrentPriorityQueue.drain(pq2)

    final_status = ConcurrentPriorityQueue.status(pq2)
    assert final_status == %{critical: 0, normal: 0, low: 0, active: 0, max_concurrency: 2}
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "drain on empty queue returns immediately", %{pq: pq} do
    assert :ok = ConcurrentPriorityQueue.drain(pq)
  end

  test "status on empty queue returns all zeros", %{pq: pq} do
    status = ConcurrentPriorityQueue.status(pq)
    assert status == %{critical: 0, normal: 0, low: 0, active: 0, max_concurrency: 1}
  end

  test "processed returns empty list when nothing has been processed", %{pq: pq} do
    assert ConcurrentPriorityQueue.processed(pq) == []
  end

  test "start_link rejects non-positive max_concurrency" do
    assert_raise ArgumentError, fn ->
      ConcurrentPriorityQueue.start_link(max_concurrency: 0)
    end

    assert_raise ArgumentError, fn ->
      ConcurrentPriorityQueue.start_link(max_concurrency: -1)
    end
  end

  # -------------------------------------------------------
  # Processor function
  # -------------------------------------------------------

  test "processor function receives and transforms the task", %{pq: _pq} do
    {:ok, pq2} =
      ConcurrentPriorityQueue.start_link(
        processor: fn n -> n * 2 end,
        max_concurrency: 1
      )

    ConcurrentPriorityQueue.enqueue(pq2, 5, :normal)
    ConcurrentPriorityQueue.enqueue(pq2, 10, :critical)
    ConcurrentPriorityQueue.drain(pq2)

    result_map = Map.new(ConcurrentPriorityQueue.processed(pq2))
    assert result_map[5] == 10
    assert result_map[10] == 20
  end

  # -------------------------------------------------------
  # Drain waits for active workers too
  # -------------------------------------------------------

  test "drain blocks until active workers finish, not just until queue is empty" do
    {:ok, pq} =
      ConcurrentPriorityQueue.start_link(
        processor: fn task ->
          Process.sleep(100)
          {:processed, task}
        end,
        max_concurrency: 3
      )

    ConcurrentPriorityQueue.enqueue(pq, "a", :normal)
    ConcurrentPriorityQueue.enqueue(pq, "b", :normal)
    ConcurrentPriorityQueue.enqueue(pq, "c", :normal)

    # Queue is drained quickly (all 3 start immediately), but workers take 100ms
    ConcurrentPriorityQueue.drain(pq)

    # If drain returned, all workers must be finished
    processed = ConcurrentPriorityQueue.processed(pq)
    assert length(processed) == 3
    status = ConcurrentPriorityQueue.status(pq)
    assert status.active == 0
  end

  # -------------------------------------------------------
  # Stress test
  # -------------------------------------------------------

  test "handles many concurrent enqueues with high concurrency" do
    {:ok, pq} =
      ConcurrentPriorityQueue.start_link(
        processor: fn task ->
          Process.sleep(1)
          {:done, task}
        end,
        max_concurrency: 10
      )

    tasks =
      for i <- 1..100 do
        priority = Enum.at([:critical, :normal, :low], rem(i, 3))
        {i, priority}
      end

    tasks
    |> Enum.map(fn {i, pri} ->
      Task.async(fn -> ConcurrentPriorityQueue.enqueue(pq, i, pri) end)
    end)
    |> Enum.each(&Task.await/1)

    ConcurrentPriorityQueue.drain(pq)

    processed = ConcurrentPriorityQueue.processed(pq)
    assert length(processed) == 100

    processed_tasks = Enum.map(processed, &elem(&1, 0)) |> Enum.sort()
    assert processed_tasks == Enum.to_list(1..100)
  end
end
```
