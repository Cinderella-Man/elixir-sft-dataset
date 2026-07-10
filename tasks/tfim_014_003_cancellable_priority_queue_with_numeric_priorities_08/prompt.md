# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule CancellablePriorityQueueTest do
  use ExUnit.Case, async: false

  defp recording_processor do
    fn task ->
      Process.sleep(5)
      {:processed, task}
    end
  end

  setup do
    {:ok, pid} =
      CancellablePriorityQueue.start_link(processor: recording_processor())

    %{pq: pid}
  end

  # -------------------------------------------------------
  # Basic enqueue / process
  # -------------------------------------------------------

  test "processes a single enqueued task", %{pq: pq} do
    assert {:ok, _ref} = CancellablePriorityQueue.enqueue(pq, "task_a", 1)
    assert :ok = CancellablePriorityQueue.drain(pq)

    assert [{"task_a", {:processed, "task_a"}}] = CancellablePriorityQueue.processed(pq)
  end

  test "enqueue returns unique refs", %{pq: pq} do
    {:ok, ref1} = CancellablePriorityQueue.enqueue(pq, "a", 0)
    {:ok, ref2} = CancellablePriorityQueue.enqueue(pq, "b", 0)
    {:ok, ref3} = CancellablePriorityQueue.enqueue(pq, "c", 1)

    assert ref1 != ref2
    assert ref2 != ref3
    assert ref1 != ref3
  end

  test "processes multiple tasks of the same priority in FIFO order", %{pq: pq} do
    CancellablePriorityQueue.enqueue(pq, "first", 5)
    CancellablePriorityQueue.enqueue(pq, "second", 5)
    CancellablePriorityQueue.enqueue(pq, "third", 5)

    CancellablePriorityQueue.drain(pq)

    tasks = CancellablePriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))
    assert tasks == ["first", "second", "third"]
  end

  # -------------------------------------------------------
  # Numeric priority ordering
  # -------------------------------------------------------

  test "lower priority numbers are processed first", %{pq: _pq} do
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      CancellablePriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end
      )

    # Occupy the processor
    CancellablePriorityQueue.enqueue(pq2, "blocker", 99)
    Process.sleep(10)

    # Enqueue in reverse priority order
    CancellablePriorityQueue.enqueue(pq2, "pri_10", 10)
    CancellablePriorityQueue.enqueue(pq2, "pri_5", 5)
    CancellablePriorityQueue.enqueue(pq2, "pri_0", 0)
    CancellablePriorityQueue.enqueue(pq2, "pri_1", 1)
    CancellablePriorityQueue.enqueue(pq2, "pri_5b", 5)

    Process.exit(gate, :kill)
    CancellablePriorityQueue.drain(pq2)

    tasks = CancellablePriorityQueue.processed(pq2) |> Enum.map(&elem(&1, 0))

    assert tasks == ["blocker", "pri_0", "pri_1", "pri_5", "pri_5b", "pri_10"]
  end

  test "priority 0 is highest", %{pq: _pq} do
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      CancellablePriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end
      )

    CancellablePriorityQueue.enqueue(pq2, "blocker", 0)
    Process.sleep(10)

    CancellablePriorityQueue.enqueue(pq2, "low", 100)
    CancellablePriorityQueue.enqueue(pq2, "urgent", 0)
    CancellablePriorityQueue.enqueue(pq2, "medium", 50)

    Process.exit(gate, :kill)
    CancellablePriorityQueue.drain(pq2)

    tasks = CancellablePriorityQueue.processed(pq2) |> Enum.map(&elem(&1, 0))
    assert tasks == ["blocker", "urgent", "medium", "low"]
  end

  # -------------------------------------------------------
  # Cancellation
  # -------------------------------------------------------

  test "cancel removes a pending task", %{pq: _pq} do
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      CancellablePriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end
      )

    CancellablePriorityQueue.enqueue(pq2, "blocker", 0)
    Process.sleep(10)

    {:ok, ref_a} = CancellablePriorityQueue.enqueue(pq2, "will_cancel", 1)
    CancellablePriorityQueue.enqueue(pq2, "will_process", 1)

    assert :ok = CancellablePriorityQueue.cancel(pq2, ref_a)

    Process.exit(gate, :kill)
    CancellablePriorityQueue.drain(pq2)

    tasks = CancellablePriorityQueue.processed(pq2) |> Enum.map(&elem(&1, 0))
    assert "will_cancel" not in tasks
    assert "will_process" in tasks
  end

  test "cancel returns error for unknown ref", %{pq: pq} do
    # TODO
  end

  test "cancel returns error for already processed task", %{pq: pq} do
    {:ok, ref} = CancellablePriorityQueue.enqueue(pq, "fast", 0)
    CancellablePriorityQueue.drain(pq)

    assert {:error, :not_found} = CancellablePriorityQueue.cancel(pq, ref)
  end

  test "double cancel returns error on second attempt", %{pq: _pq} do
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      CancellablePriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end
      )

    CancellablePriorityQueue.enqueue(pq2, "blocker", 0)
    Process.sleep(10)

    {:ok, ref} = CancellablePriorityQueue.enqueue(pq2, "target", 1)

    assert :ok = CancellablePriorityQueue.cancel(pq2, ref)
    assert {:error, :not_found} = CancellablePriorityQueue.cancel(pq2, ref)

    Process.exit(gate, :kill)
    CancellablePriorityQueue.drain(pq2)
  end

  test "cancelled count is tracked in status", %{pq: _pq} do
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      CancellablePriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end
      )

    CancellablePriorityQueue.enqueue(pq2, "blocker", 0)
    Process.sleep(10)

    {:ok, ref1} = CancellablePriorityQueue.enqueue(pq2, "a", 1)
    {:ok, ref2} = CancellablePriorityQueue.enqueue(pq2, "b", 2)
    CancellablePriorityQueue.enqueue(pq2, "c", 3)

    CancellablePriorityQueue.cancel(pq2, ref1)
    CancellablePriorityQueue.cancel(pq2, ref2)

    status = CancellablePriorityQueue.status(pq2)
    assert status.cancelled == 2
    assert status.pending == 1

    Process.exit(gate, :kill)
    CancellablePriorityQueue.drain(pq2)
  end

  # -------------------------------------------------------
  # Status reporting
  # -------------------------------------------------------

  test "status reports pending counts by priority", %{pq: _pq} do
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      CancellablePriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end
      )

    CancellablePriorityQueue.enqueue(pq2, "blocker", 99)
    Process.sleep(10)

    CancellablePriorityQueue.enqueue(pq2, "a", 0)
    CancellablePriorityQueue.enqueue(pq2, "b", 0)
    CancellablePriorityQueue.enqueue(pq2, "c", 5)
    CancellablePriorityQueue.enqueue(pq2, "d", 10)
    CancellablePriorityQueue.enqueue(pq2, "e", 10)

    status = CancellablePriorityQueue.status(pq2)
    assert status.pending == 5
    assert status.by_priority == %{0 => 2, 5 => 1, 10 => 2}
    assert status.cancelled == 0

    Process.exit(gate, :kill)
    CancellablePriorityQueue.drain(pq2)

    final_status = CancellablePriorityQueue.status(pq2)
    assert final_status.pending == 0
    assert final_status.by_priority == %{}
  end

  # -------------------------------------------------------
  # Peek
  # -------------------------------------------------------

  test "peek returns the next task without removing it", %{pq: _pq} do
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      CancellablePriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end
      )

    CancellablePriorityQueue.enqueue(pq2, "blocker", 0)
    Process.sleep(10)

    CancellablePriorityQueue.enqueue(pq2, "low", 10)
    CancellablePriorityQueue.enqueue(pq2, "high", 1)

    assert {:ok, "high", 1} = CancellablePriorityQueue.peek(pq2)
    # Peek again — still there
    assert {:ok, "high", 1} = CancellablePriorityQueue.peek(pq2)

    Process.exit(gate, :kill)
    CancellablePriorityQueue.drain(pq2)
  end

  test "peek on empty queue returns :empty", %{pq: pq} do
    assert :empty = CancellablePriorityQueue.peek(pq)
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "drain on empty queue returns immediately", %{pq: pq} do
    assert :ok = CancellablePriorityQueue.drain(pq)
  end

  test "status on empty queue returns all zeros", %{pq: pq} do
    status = CancellablePriorityQueue.status(pq)
    assert status == %{pending: 0, by_priority: %{}, cancelled: 0}
  end

  test "processed returns empty list when nothing has been processed", %{pq: pq} do
    assert CancellablePriorityQueue.processed(pq) == []
  end

  # -------------------------------------------------------
  # Processor function
  # -------------------------------------------------------

  test "processor function receives and transforms the task", %{pq: _pq} do
    {:ok, pq2} =
      CancellablePriorityQueue.start_link(processor: fn n -> n * 2 end)

    CancellablePriorityQueue.enqueue(pq2, 5, 1)
    CancellablePriorityQueue.enqueue(pq2, 10, 0)
    CancellablePriorityQueue.drain(pq2)

    result_map = Map.new(CancellablePriorityQueue.processed(pq2))
    assert result_map[5] == 10
    assert result_map[10] == 20
  end

  # -------------------------------------------------------
  # Concurrent stress test
  # -------------------------------------------------------

  test "handles many concurrent enqueues without losing tasks", %{pq: _pq} do
    {:ok, pq2} =
      CancellablePriorityQueue.start_link(
        processor: fn task ->
          Process.sleep(1)
          {:done, task}
        end
      )

    tasks =
      for i <- 1..50 do
        priority = rem(i, 10)
        {i, priority}
      end

    tasks
    |> Enum.map(fn {i, pri} ->
      Task.async(fn -> CancellablePriorityQueue.enqueue(pq2, i, pri) end)
    end)
    |> Enum.each(&Task.await/1)

    CancellablePriorityQueue.drain(pq2)

    processed = CancellablePriorityQueue.processed(pq2)
    assert length(processed) == 50

    processed_tasks = Enum.map(processed, &elem(&1, 0)) |> Enum.sort()
    assert processed_tasks == Enum.to_list(1..50)
  end

  # -------------------------------------------------------
  # Cancel + priority interaction
  # -------------------------------------------------------

  test "cancelling highest priority task causes next priority to be processed first", %{pq: _pq} do
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      CancellablePriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end
      )

    CancellablePriorityQueue.enqueue(pq2, "blocker", 0)
    Process.sleep(10)

    {:ok, high_ref} = CancellablePriorityQueue.enqueue(pq2, "high_cancelled", 0)
    CancellablePriorityQueue.enqueue(pq2, "medium", 5)
    CancellablePriorityQueue.enqueue(pq2, "low", 10)

    CancellablePriorityQueue.cancel(pq2, high_ref)

    Process.exit(gate, :kill)
    CancellablePriorityQueue.drain(pq2)

    tasks = CancellablePriorityQueue.processed(pq2) |> Enum.map(&elem(&1, 0))
    assert tasks == ["blocker", "medium", "low"]
  end
end
```
