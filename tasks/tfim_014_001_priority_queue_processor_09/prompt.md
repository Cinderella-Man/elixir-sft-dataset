# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule PriorityQueueTest do
  use ExUnit.Case, async: false

  # A processor that records what it processed and simulates a tiny delay
  # so we can reason about ordering deterministically.
  defp recording_processor do
    fn task ->
      # Small sleep to make sure messages are queued before being consumed
      Process.sleep(5)
      {:processed, task}
    end
  end

  setup do
    {:ok, pid} =
      PriorityQueue.start_link(processor: recording_processor())

    %{pq: pid}
  end

  # -------------------------------------------------------
  # Basic enqueue / process
  # -------------------------------------------------------

  test "processes a single enqueued task", %{pq: pq} do
    assert :ok = PriorityQueue.enqueue(pq, "task_a", :normal)
    assert :ok = PriorityQueue.drain(pq)

    assert [{"task_a", {:processed, "task_a"}}] = PriorityQueue.processed(pq)
  end

  test "processes multiple tasks of the same priority in FIFO order", %{pq: pq} do
    PriorityQueue.enqueue(pq, "first", :normal)
    PriorityQueue.enqueue(pq, "second", :normal)
    PriorityQueue.enqueue(pq, "third", :normal)

    PriorityQueue.drain(pq)

    tasks = PriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))
    assert tasks == ["first", "second", "third"]
  end

  # -------------------------------------------------------
  # Priority ordering
  # -------------------------------------------------------

  test "high priority tasks are processed before normal and low", %{pq: pq} do
    # Enqueue a low-priority task first so the processor picks it up
    # and is busy while we enqueue the rest.
    PriorityQueue.enqueue(pq, "low_1", :low)

    # Give processor a moment to start on low_1
    Process.sleep(2)

    # Now enqueue mixed priorities while processor is busy
    PriorityQueue.enqueue(pq, "low_2", :low)
    PriorityQueue.enqueue(pq, "normal_1", :normal)
    PriorityQueue.enqueue(pq, "high_1", :high)
    PriorityQueue.enqueue(pq, "normal_2", :normal)
    PriorityQueue.enqueue(pq, "high_2", :high)

    PriorityQueue.drain(pq)

    tasks = PriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))

    # low_1 was already being processed, so it comes first.
    # After that: high_1, high_2 (high FIFO), normal_1, normal_2 (normal FIFO), low_2
    assert tasks == ["low_1", "high_1", "high_2", "normal_1", "normal_2", "low_2"]
  end

  test "high beats normal beats low in a clean queue", %{pq: _pq} do
    # Use a processor with a gate so nothing starts until we've enqueued everything
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      PriorityQueue.start_link(
        processor: fn task ->
          # Block until gate process is dead (will be killed below)
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end
      )

    # Enqueue one task to occupy the processor at the gate
    PriorityQueue.enqueue(pq2, "blocker", :low)
    Process.sleep(10)

    # Queue up tasks in reverse priority order
    PriorityQueue.enqueue(pq2, "low_a", :low)
    PriorityQueue.enqueue(pq2, "low_b", :low)
    PriorityQueue.enqueue(pq2, "normal_a", :normal)
    PriorityQueue.enqueue(pq2, "normal_b", :normal)
    PriorityQueue.enqueue(pq2, "high_a", :high)
    PriorityQueue.enqueue(pq2, "high_b", :high)

    # Release the gate — all queued tasks will now be processed in priority order
    Process.exit(gate, :kill)

    PriorityQueue.drain(pq2)

    tasks = PriorityQueue.processed(pq2) |> Enum.map(&elem(&1, 0))

    # blocker was already running, then strict priority order
    assert tasks == [
             "blocker",
             "high_a",
             "high_b",
             "normal_a",
             "normal_b",
             "low_a",
             "low_b"
           ]
  end

  # -------------------------------------------------------
  # Status reporting
  # -------------------------------------------------------

  test "status reports pending counts accurately", %{pq: _pq} do
    # Use a gated processor so tasks pile up
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      PriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end
      )

    # Enqueue one to occupy the processor
    PriorityQueue.enqueue(pq2, "blocker", :normal)
    Process.sleep(10)

    # These will all be pending
    PriorityQueue.enqueue(pq2, "h1", :high)
    PriorityQueue.enqueue(pq2, "h2", :high)
    PriorityQueue.enqueue(pq2, "n1", :normal)
    PriorityQueue.enqueue(pq2, "l1", :low)
    PriorityQueue.enqueue(pq2, "l2", :low)
    PriorityQueue.enqueue(pq2, "l3", :low)

    status = PriorityQueue.status(pq2)
    assert status.high == 2
    assert status.normal == 1
    assert status.low == 3

    # Release and let everything finish
    Process.exit(gate, :kill)
    PriorityQueue.drain(pq2)

    status_after = PriorityQueue.status(pq2)
    assert status_after == %{high: 0, normal: 0, low: 0}
  end

  # -------------------------------------------------------
  # FIFO within priority
  # -------------------------------------------------------

  test "FIFO is maintained within each priority level", %{pq: _pq} do
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      PriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end
      )

    PriorityQueue.enqueue(pq2, "l_blocker", :low)
    Process.sleep(10)

    # Enqueue several tasks per level
    PriorityQueue.enqueue(pq2, "n1", :normal)
    PriorityQueue.enqueue(pq2, "n2", :normal)
    PriorityQueue.enqueue(pq2, "n3", :normal)
    PriorityQueue.enqueue(pq2, "h1", :high)
    PriorityQueue.enqueue(pq2, "h2", :high)
    PriorityQueue.enqueue(pq2, "l1", :low)
    PriorityQueue.enqueue(pq2, "l2", :low)

    Process.exit(gate, :kill)
    PriorityQueue.drain(pq2)

    tasks = PriorityQueue.processed(pq2) |> Enum.map(&elem(&1, 0))

    # Extract subsequences per priority
    high_tasks = Enum.filter(tasks, &String.starts_with?(&1, "h"))
    normal_tasks = Enum.filter(tasks, &String.starts_with?(&1, "n"))
    low_tasks = Enum.filter(tasks, &String.starts_with?(&1, "l"))

    assert high_tasks == ["h1", "h2"]
    assert normal_tasks == ["n1", "n2", "n3"]
    assert low_tasks == ["l_blocker", "l1", "l2"]
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "drain on empty queue returns immediately", %{pq: pq} do
    assert :ok = PriorityQueue.drain(pq)
  end

  test "status on empty queue returns all zeros", %{pq: pq} do
    # TODO
  end

  test "processed returns empty list when nothing has been processed", %{pq: pq} do
    assert PriorityQueue.processed(pq) == []
  end

  test "enqueue with all three priorities in reverse order", %{pq: _pq} do
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      PriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end
      )

    PriorityQueue.enqueue(pq2, "blocker", :high)
    Process.sleep(10)

    PriorityQueue.enqueue(pq2, "low_only", :low)
    PriorityQueue.enqueue(pq2, "normal_only", :normal)
    PriorityQueue.enqueue(pq2, "high_only", :high)

    Process.exit(gate, :kill)
    PriorityQueue.drain(pq2)

    tasks = PriorityQueue.processed(pq2) |> Enum.map(&elem(&1, 0))
    assert tasks == ["blocker", "high_only", "normal_only", "low_only"]
  end

  # -------------------------------------------------------
  # Idle transition after draining
  # -------------------------------------------------------

  test "becomes idle after draining and processes tasks enqueued later", %{pq: pq} do
    PriorityQueue.enqueue(pq, "batch1", :normal)
    assert :ok = PriorityQueue.drain(pq)
    assert [{"batch1", {:processed, "batch1"}}] = PriorityQueue.processed(pq)

    # Once the queue has fully drained the processor must be idle again, so a
    # brand new task enqueued now must trigger processing on its own. If the
    # server stayed "busy", this second drain would never return.
    PriorityQueue.enqueue(pq, "batch2", :high)
    assert :ok = PriorityQueue.drain(pq)

    tasks = PriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))
    assert tasks == ["batch1", "batch2"]
  end

  test "repeated drain/enqueue cycles keep processing each new task", %{pq: pq} do
    for n <- 1..5 do
      PriorityQueue.enqueue(pq, n, :normal)
      assert :ok = PriorityQueue.drain(pq)

      processed_so_far = PriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))
      assert processed_so_far == Enum.to_list(1..n)
    end
  end

  # -------------------------------------------------------
  # Processor function receives the task value
  # -------------------------------------------------------

  test "processor function receives and transforms the task", %{pq: _pq} do
    {:ok, pq2} =
      PriorityQueue.start_link(processor: fn n -> n * 2 end)

    PriorityQueue.enqueue(pq2, 5, :normal)
    PriorityQueue.enqueue(pq2, 10, :high)
    PriorityQueue.drain(pq2)

    results = PriorityQueue.processed(pq2)

    # high comes first if it was queued before processing started,
    # but with fast processing, ordering may vary.
    # Just check both tasks were processed with correct results.
    assert {5, 10} in results or {10, 20} in results
    result_map = Map.new(results)
    assert result_map[5] == 10
    assert result_map[10] == 20
  end

  # -------------------------------------------------------
  # Concurrent enqueue stress test
  # -------------------------------------------------------

  test "handles many concurrent enqueues without losing tasks", %{pq: _pq} do
    {:ok, pq2} =
      PriorityQueue.start_link(
        processor: fn task ->
          Process.sleep(1)
          {:done, task}
        end
      )

    tasks =
      for i <- 1..50 do
        priority = Enum.at([:high, :normal, :low], rem(i, 3))
        {i, priority}
      end

    # Enqueue from multiple processes concurrently
    tasks
    |> Enum.map(fn {i, pri} ->
      Task.async(fn -> PriorityQueue.enqueue(pq2, i, pri) end)
    end)
    |> Enum.each(&Task.await/1)

    PriorityQueue.drain(pq2)

    processed = PriorityQueue.processed(pq2)
    assert length(processed) == 50

    # Verify all tasks were processed (order may vary due to concurrent enqueue)
    processed_tasks = Enum.map(processed, &elem(&1, 0)) |> Enum.sort()
    assert processed_tasks == Enum.to_list(1..50)
  end

  test "default processor returns the task unchanged when :processor omitted" do
    {:ok, pq2} = PriorityQueue.start_link([])

    assert :ok = PriorityQueue.enqueue(pq2, "echo_me", :normal)
    assert :ok = PriorityQueue.drain(pq2)

    assert PriorityQueue.processed(pq2) == [{"echo_me", "echo_me"}]
  end

  test "registers under the given :name and is reachable by that name" do
    name = :priority_queue_named_registration_test

    {:ok, _pid} =
      PriorityQueue.start_link(name: name, processor: fn t -> {:ok, t} end)

    assert :ok = PriorityQueue.enqueue(name, "named_task", :high)
    assert :ok = PriorityQueue.drain(name)

    assert PriorityQueue.processed(name) == [{"named_task", {:ok, "named_task"}}]
  end
end
```
