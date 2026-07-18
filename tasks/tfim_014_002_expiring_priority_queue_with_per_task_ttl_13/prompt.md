# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

      {:ok, task, state} ->
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

## Test harness — implement the `# TODO` test

```elixir
defmodule ExpiringPriorityQueueTest do
  use ExUnit.Case, async: false

  defp start_clock(initial) do
    {:ok, agent} = Agent.start_link(fn -> initial end)
    agent
  end

  defp advance_clock(agent, ms) do
    Agent.update(agent, fn t -> t + ms end)
  end

  defp clock_fn(agent) do
    fn -> Agent.get(agent, & &1) end
  end

  defp recording_processor do
    fn task ->
      Process.sleep(5)
      {:processed, task}
    end
  end

  # Calls drain/1 without risking an infinite block: returns {:ok, :ok} when the
  # queue drains within `timeout`, and nil (via Task.shutdown) when it does not.
  defp await_drain(pq, timeout \\ 2000) do
    task = Task.async(fn -> ExpiringPriorityQueue.drain(pq) end)
    Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill)
  end

  # -------------------------------------------------------
  # Basic enqueue / process
  # -------------------------------------------------------

  test "processes a single enqueued task" do
    clock_agent = start_clock(0)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: recording_processor(),
        clock: clock_fn(clock_agent),
        default_ttl_ms: 10_000
      )

    assert :ok = ExpiringPriorityQueue.enqueue(pq, "task_a", :normal)
    assert :ok = ExpiringPriorityQueue.drain(pq)

    assert [{"task_a", {:processed, "task_a"}}] = ExpiringPriorityQueue.processed(pq)
    assert [] = ExpiringPriorityQueue.expired(pq)
  end

  test "processes multiple tasks of the same priority in FIFO order" do
    clock_agent = start_clock(0)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: recording_processor(),
        clock: clock_fn(clock_agent),
        default_ttl_ms: 10_000
      )

    ExpiringPriorityQueue.enqueue(pq, "first", :normal)
    ExpiringPriorityQueue.enqueue(pq, "second", :normal)
    ExpiringPriorityQueue.enqueue(pq, "third", :normal)

    ExpiringPriorityQueue.drain(pq)

    tasks = ExpiringPriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))
    assert tasks == ["first", "second", "third"]
  end

  # -------------------------------------------------------
  # Priority ordering
  # -------------------------------------------------------

  test "high priority tasks are processed before normal and low" do
    clock_agent = start_clock(0)

    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end,
        clock: clock_fn(clock_agent),
        default_ttl_ms: 100_000
      )

    # Occupy the processor
    ExpiringPriorityQueue.enqueue(pq, "blocker", :low)
    Process.sleep(10)

    # Queue up tasks in reverse priority order
    ExpiringPriorityQueue.enqueue(pq, "low_a", :low)
    ExpiringPriorityQueue.enqueue(pq, "normal_a", :normal)
    ExpiringPriorityQueue.enqueue(pq, "high_a", :high)
    ExpiringPriorityQueue.enqueue(pq, "normal_b", :normal)
    ExpiringPriorityQueue.enqueue(pq, "high_b", :high)

    Process.exit(gate, :kill)
    ExpiringPriorityQueue.drain(pq)

    tasks = ExpiringPriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))

    assert tasks == [
             "blocker",
             "high_a",
             "high_b",
             "normal_a",
             "normal_b",
             "low_a"
           ]
  end

  # -------------------------------------------------------
  # TTL / Expiration
  # -------------------------------------------------------

  test "expired tasks are skipped and recorded" do
    clock_agent = start_clock(0)
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end,
        clock: clock_fn(clock_agent),
        default_ttl_ms: 100
      )

    # Occupy the processor with a blocker that has a long TTL
    ExpiringPriorityQueue.enqueue(pq, "blocker", :normal, ttl_ms: 100_000)
    Process.sleep(10)

    # Enqueue a task with default short TTL — it stays queued
    ExpiringPriorityQueue.enqueue(pq, "will_expire", :normal)

    # Enqueue a task with long TTL
    ExpiringPriorityQueue.enqueue(pq, "still_valid", :normal, ttl_ms: 50_000)

    # Advance clock past default TTL
    advance_clock(clock_agent, 200)

    # Release the gate — blocker finishes, then process_next finds will_expire is expired
    Process.exit(gate, :kill)
    ExpiringPriorityQueue.drain(pq)

    processed = ExpiringPriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))
    expired = ExpiringPriorityQueue.expired(pq)

    assert processed == ["blocker", "still_valid"]
    assert [{"will_expire", :normal}] = expired
  end

  test "per-task TTL overrides default TTL" do
    clock_agent = start_clock(0)
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end,
        clock: clock_fn(clock_agent),
        default_ttl_ms: 1000
      )

    # Occupy the processor
    ExpiringPriorityQueue.enqueue(pq, "blocker", :high, ttl_ms: 100_000)
    Process.sleep(10)

    # Short custom TTL
    ExpiringPriorityQueue.enqueue(pq, "short_ttl", :normal, ttl_ms: 50)
    # Uses default TTL (1000ms)
    ExpiringPriorityQueue.enqueue(pq, "default_ttl", :normal)

    # Advance clock past short TTL but within default TTL
    advance_clock(clock_agent, 100)

    Process.exit(gate, :kill)
    ExpiringPriorityQueue.drain(pq)

    processed_tasks = ExpiringPriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))
    expired_tasks = ExpiringPriorityQueue.expired(pq) |> Enum.map(&elem(&1, 0))

    assert processed_tasks == ["blocker", "default_ttl"]
    assert expired_tasks == ["short_ttl"]
  end

  test "multiple expired tasks are skipped in sequence before finding a valid one" do
    clock_agent = start_clock(0)
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end,
        clock: clock_fn(clock_agent),
        default_ttl_ms: 50
      )

    # Occupy processor
    ExpiringPriorityQueue.enqueue(pq, "blocker", :low, ttl_ms: 100_000)
    Process.sleep(10)

    # Enqueue several tasks with short TTL
    ExpiringPriorityQueue.enqueue(pq, "expire_1", :high)
    ExpiringPriorityQueue.enqueue(pq, "expire_2", :high)
    ExpiringPriorityQueue.enqueue(pq, "expire_3", :normal)
    # One with long TTL
    ExpiringPriorityQueue.enqueue(pq, "survivor", :low, ttl_ms: 100_000)

    # Advance past short TTL
    advance_clock(clock_agent, 100)

    Process.exit(gate, :kill)
    ExpiringPriorityQueue.drain(pq)

    processed = ExpiringPriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))
    expired = ExpiringPriorityQueue.expired(pq) |> Enum.map(&elem(&1, 0))

    assert processed == ["blocker", "survivor"]
    assert expired == ["expire_1", "expire_2", "expire_3"]
  end

  test "expired tasks record their original priority" do
    clock_agent = start_clock(0)
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end,
        clock: clock_fn(clock_agent),
        default_ttl_ms: 50
      )

    # Occupy processor
    ExpiringPriorityQueue.enqueue(pq, "blocker", :normal, ttl_ms: 100_000)
    Process.sleep(10)

    ExpiringPriorityQueue.enqueue(pq, "high_expired", :high)
    ExpiringPriorityQueue.enqueue(pq, "low_expired", :low)

    advance_clock(clock_agent, 100)

    Process.exit(gate, :kill)
    ExpiringPriorityQueue.drain(pq)

    expired = ExpiringPriorityQueue.expired(pq)
    assert {"high_expired", :high} in expired
    assert {"low_expired", :low} in expired
  end

  test "all tasks expired results in empty processed list (except blocker)" do
    clock_agent = start_clock(0)
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end,
        clock: clock_fn(clock_agent),
        default_ttl_ms: 50
      )

    # Occupy processor
    ExpiringPriorityQueue.enqueue(pq, "blocker", :low, ttl_ms: 100_000)
    Process.sleep(10)

    ExpiringPriorityQueue.enqueue(pq, "a", :high)
    ExpiringPriorityQueue.enqueue(pq, "b", :normal)
    ExpiringPriorityQueue.enqueue(pq, "c", :low)

    advance_clock(clock_agent, 100)

    Process.exit(gate, :kill)
    ExpiringPriorityQueue.drain(pq)

    processed = ExpiringPriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))
    assert processed == ["blocker"]
    assert length(ExpiringPriorityQueue.expired(pq)) == 3
  end

  # -------------------------------------------------------
  # Status reporting
  # -------------------------------------------------------

  test "status reports pending counts excluding expired tasks" do
    clock_agent = start_clock(0)
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end,
        clock: clock_fn(clock_agent),
        default_ttl_ms: 50
      )

    # Occupy the processor
    ExpiringPriorityQueue.enqueue(pq, "blocker", :normal, ttl_ms: 100_000)
    Process.sleep(10)

    # Enqueue tasks — some will expire
    ExpiringPriorityQueue.enqueue(pq, "h1", :high, ttl_ms: 100_000)
    ExpiringPriorityQueue.enqueue(pq, "h2_short", :high, ttl_ms: 50)
    ExpiringPriorityQueue.enqueue(pq, "n1", :normal, ttl_ms: 100_000)
    ExpiringPriorityQueue.enqueue(pq, "l1_short", :low, ttl_ms: 50)

    # Advance clock to expire the short-TTL tasks
    advance_clock(clock_agent, 100)

    status = ExpiringPriorityQueue.status(pq)
    assert status.high == 1
    assert status.normal == 1
    assert status.low == 0

    Process.exit(gate, :kill)
    ExpiringPriorityQueue.drain(pq)
  end

  test "status shows expired count after processing" do
    clock_agent = start_clock(0)
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end,
        clock: clock_fn(clock_agent),
        default_ttl_ms: 50
      )

    # Occupy processor
    ExpiringPriorityQueue.enqueue(pq, "blocker", :normal, ttl_ms: 100_000)
    Process.sleep(10)

    ExpiringPriorityQueue.enqueue(pq, "a", :high)
    ExpiringPriorityQueue.enqueue(pq, "b", :normal)

    advance_clock(clock_agent, 100)

    Process.exit(gate, :kill)
    ExpiringPriorityQueue.drain(pq)

    status = ExpiringPriorityQueue.status(pq)
    assert status.expired == 2
  end

  # -------------------------------------------------------
  # TTL boundary: the instant a task's TTL elapses it is expired
  # -------------------------------------------------------

  test "a task whose expiry equals the current clock is expired, not pending" do
    clock_agent = start_clock(0)
    parent = self()
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: fn task ->
          if task == "blocker" do
            send(parent, :blocker_started)
            ref = Process.monitor(gate)

            receive do
              {:DOWN, ^ref, _, _, _} -> :ok
            end
          end

          {:processed, task}
        end,
        clock: clock_fn(clock_agent),
        default_ttl_ms: 100_000
      )

    # Occupy the processor so "boundary" stays queued while we move the clock.
    ExpiringPriorityQueue.enqueue(pq, "blocker", :normal, ttl_ms: 100_000)
    assert_receive :blocker_started, 2000

    # Enqueued at clock 0 with a 1000ms TTL -> expires_at == 1000.
    ExpiringPriorityQueue.enqueue(pq, "boundary", :high, ttl_ms: 1000)

    # One tick before the deadline the task is still pending.
    advance_clock(clock_agent, 999)
    assert ExpiringPriorityQueue.status(pq).high == 1

    # Exactly at the deadline the TTL window is over: the task is no longer pending.
    advance_clock(clock_agent, 1)
    assert ExpiringPriorityQueue.status(pq).high == 0

    Process.exit(gate, :kill)
    ExpiringPriorityQueue.drain(pq)

    # ...and picking it up at exactly expires_at records it as expired, not processed.
    assert ExpiringPriorityQueue.expired(pq) == [{"boundary", :high}]
    assert Enum.map(ExpiringPriorityQueue.processed(pq), &elem(&1, 0)) == ["blocker"]
  end

  # -------------------------------------------------------
  # Returning to idle
  # -------------------------------------------------------

  test "queue returns to idle after a task finishes so later enqueues still run" do
    # TODO
  end

  test "queue returns to idle after a round where every candidate task expired" do
    clock_agent = start_clock(0)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: recording_processor(),
        clock: clock_fn(clock_agent),
        default_ttl_ms: 100_000
      )

    # A zero TTL expires the moment :process_next looks at it, so this round of
    # processing finds nothing to run and must leave the processor idle.
    assert :ok = ExpiringPriorityQueue.enqueue(pq, "dead", :normal, ttl_ms: 0)
    assert ExpiringPriorityQueue.expired(pq) == [{"dead", :normal}]
    assert ExpiringPriorityQueue.processed(pq) == []

    # Idle again: this task must be picked up.
    assert :ok = ExpiringPriorityQueue.enqueue(pq, "alive", :normal, ttl_ms: 100_000)
    assert await_drain(pq) == {:ok, :ok}

    assert ExpiringPriorityQueue.processed(pq) == [{"alive", {:processed, "alive"}}]
    assert ExpiringPriorityQueue.expired(pq) == [{"dead", :normal}]
    assert ExpiringPriorityQueue.status(pq) == %{high: 0, normal: 0, low: 0, expired: 1}
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "drain on empty queue returns immediately" do
    clock_agent = start_clock(0)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        clock: clock_fn(clock_agent),
        default_ttl_ms: 5000
      )

    assert :ok = ExpiringPriorityQueue.drain(pq)
  end

  test "status on empty queue returns all zeros" do
    clock_agent = start_clock(0)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        clock: clock_fn(clock_agent),
        default_ttl_ms: 5000
      )

    assert ExpiringPriorityQueue.status(pq) == %{high: 0, normal: 0, low: 0, expired: 0}
  end

  test "processed and expired return empty lists when nothing has been enqueued" do
    clock_agent = start_clock(0)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        clock: clock_fn(clock_agent),
        default_ttl_ms: 5000
      )

    assert ExpiringPriorityQueue.processed(pq) == []
    assert ExpiringPriorityQueue.expired(pq) == []
  end

  # -------------------------------------------------------
  # Processor function receives and transforms
  # -------------------------------------------------------

  test "processor function receives and transforms the task" do
    clock_agent = start_clock(0)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: fn n -> n * 2 end,
        clock: clock_fn(clock_agent),
        default_ttl_ms: 100_000
      )

    ExpiringPriorityQueue.enqueue(pq, 5, :normal)
    ExpiringPriorityQueue.enqueue(pq, 10, :high)
    ExpiringPriorityQueue.drain(pq)

    result_map = Map.new(ExpiringPriorityQueue.processed(pq))
    assert result_map[5] == 10
    assert result_map[10] == 20
  end

  # -------------------------------------------------------
  # Concurrent stress test
  # -------------------------------------------------------

  test "handles many concurrent enqueues without losing non-expired tasks" do
    clock_agent = start_clock(0)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: fn task ->
          Process.sleep(1)
          {:done, task}
        end,
        clock: clock_fn(clock_agent),
        default_ttl_ms: 1_000_000
      )

    tasks =
      for i <- 1..50 do
        priority = Enum.at([:high, :normal, :low], rem(i, 3))
        {i, priority}
      end

    tasks
    |> Enum.map(fn {i, pri} ->
      Task.async(fn -> ExpiringPriorityQueue.enqueue(pq, i, pri) end)
    end)
    |> Enum.each(&Task.await/1)

    ExpiringPriorityQueue.drain(pq)

    processed = ExpiringPriorityQueue.processed(pq)
    assert length(processed) == 50

    processed_tasks = Enum.map(processed, &elem(&1, 0)) |> Enum.sort()
    assert processed_tasks == Enum.to_list(1..50)
  end

  test "default_ttl_ms defaults to 5000 when the option is omitted" do
    clock_agent = start_clock(0)
    parent = self()
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: fn task ->
          if task == "blocker" do
            send(parent, :blocker_started)
            ref = Process.monitor(gate)

            receive do
              {:DOWN, ^ref, _, _, _} -> :ok
            end
          end

          {:processed, task}
        end,
        clock: clock_fn(clock_agent)
      )

    ExpiringPriorityQueue.enqueue(pq, "blocker", :normal, ttl_ms: 100_000)
    assert_receive :blocker_started, 2000

    ExpiringPriorityQueue.enqueue(pq, "uses_default", :normal)

    advance_clock(clock_agent, 4999)
    assert ExpiringPriorityQueue.status(pq).normal == 1

    advance_clock(clock_agent, 2)
    assert ExpiringPriorityQueue.status(pq).normal == 0

    Process.exit(gate, :kill)
    ExpiringPriorityQueue.drain(pq)

    assert ExpiringPriorityQueue.expired(pq) == [{"uses_default", :normal}]
    assert Enum.map(ExpiringPriorityQueue.processed(pq), &elem(&1, 0)) == ["blocker"]
  end

  test "identical ttl_ms values expire relative to each task's own enqueue time" do
    clock_agent = start_clock(0)
    parent = self()
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: fn task ->
          if task == "blocker" do
            send(parent, :blocker_started)
            ref = Process.monitor(gate)

            receive do
              {:DOWN, ^ref, _, _, _} -> :ok
            end
          end

          {:processed, task}
        end,
        clock: clock_fn(clock_agent),
        default_ttl_ms: 100_000
      )

    ExpiringPriorityQueue.enqueue(pq, "blocker", :normal, ttl_ms: 100_000)
    assert_receive :blocker_started, 2000

    # Enqueued at clock 0 -> expires at 1000
    ExpiringPriorityQueue.enqueue(pq, "early", :normal, ttl_ms: 1000)

    advance_clock(clock_agent, 800)

    # Same ttl_ms, but enqueued at clock 800 -> expires at 1800
    ExpiringPriorityQueue.enqueue(pq, "late", :normal, ttl_ms: 1000)

    advance_clock(clock_agent, 400)

    Process.exit(gate, :kill)
    ExpiringPriorityQueue.drain(pq)

    assert Enum.map(ExpiringPriorityQueue.processed(pq), &elem(&1, 0)) == ["blocker", "late"]
    assert ExpiringPriorityQueue.expired(pq) == [{"early", :normal}]
  end

  test "the :name option registers the server so the API can be driven by name" do
    clock_agent = start_clock(0)
    name = :expiring_priority_queue_named_server

    {:ok, pid} =
      ExpiringPriorityQueue.start_link(
        name: name,
        processor: fn task -> {:ok, task} end,
        clock: clock_fn(clock_agent),
        default_ttl_ms: 10_000
      )

    assert Process.whereis(name) == pid

    assert :ok = ExpiringPriorityQueue.enqueue(name, "named", :normal)
    assert :ok = ExpiringPriorityQueue.drain(name)

    assert ExpiringPriorityQueue.processed(name) == [{"named", {:ok, "named"}}]
    assert ExpiringPriorityQueue.expired(name) == []
    assert ExpiringPriorityQueue.status(name) == %{high: 0, normal: 0, low: 0, expired: 0}
  end

  test "enqueue refuses a priority outside high, normal and low" do
    clock_agent = start_clock(0)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: recording_processor(),
        clock: clock_fn(clock_agent),
        default_ttl_ms: 10_000
      )

    assert_raise FunctionClauseError, fn ->
      ExpiringPriorityQueue.enqueue(pq, "bad", :urgent)
    end

    assert_raise FunctionClauseError, fn ->
      ExpiringPriorityQueue.enqueue(pq, "bad", "high", ttl_ms: 100)
    end

    assert ExpiringPriorityQueue.status(pq) == %{high: 0, normal: 0, low: 0, expired: 0}
    assert ExpiringPriorityQueue.processed(pq) == []
  end
end
```
