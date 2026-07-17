# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule PriorityWorkerPool do
  @moduledoc """
  A priority-based bounded-queue worker pool with starvation prevention.
  """

  use GenServer

  @priorities [:high, :normal, :low]

  ## --- Public API ---

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Submits `task_func` at `priority`, with starvation prevention. Returns `{:ok, ref}`."
  @spec submit(GenServer.server(), (-> any()), :high | :normal | :low) ::
          {:ok, reference()} | {:error, :queue_full}
  def submit(pool, task_func, priority \\ :normal)
      when is_function(task_func, 0) and priority in @priorities do
    GenServer.call(pool, {:submit, task_func, priority})
  end

  @spec await(GenServer.server(), reference(), non_neg_integer()) ::
          {:ok, any()} | {:error, any()}
  def await(_pool, ref, timeout \\ 5_000) when is_reference(ref) do
    receive do
      {^ref, :result, result} -> {:ok, result}
      {^ref, :error, reason} -> {:error, reason}
    after
      timeout -> {:error, :timeout}
    end
  end

  @spec status(GenServer.server()) :: map()
  def status(pool) do
    GenServer.call(pool, :status)
  end

  ## --- Server Callbacks ---

  defmodule State do
    defstruct [
      :sup,
      :max_queue,
      :pool_size,
      :promote_after_ms,
      # %{priority => :queue.queue({ref, client_pid, func, enqueued_at})}
      queues: %{high: :queue.new(), normal: :queue.new(), low: :queue.new()},
      idle_workers: [],
      busy_workers: %{},
      monitors: %{}
    ]
  end

  @impl true
  def init(opts) do
    pool_size = Keyword.get(opts, :pool_size, 3)
    max_queue = Keyword.get(opts, :max_queue, 10)
    promote_after_ms = Keyword.get(opts, :promote_after_ms, 5_000)

    {:ok, sup} = DynamicSupervisor.start_link(strategy: :one_for_one)

    state = %State{
      sup: sup,
      pool_size: pool_size,
      max_queue: max_queue,
      promote_after_ms: promote_after_ms
    }

    new_state =
      Enum.reduce(1..pool_size, state, fn _, acc ->
        {:ok, pid} = start_worker(acc.sup)
        mref = Process.monitor(pid)

        %{
          acc
          | idle_workers: [pid | acc.idle_workers],
            monitors: Map.put(acc.monitors, mref, pid)
        }
      end)

    schedule_promotion(promote_after_ms)

    {:ok, new_state}
  end

  @impl true
  def handle_call({:submit, task_func, priority}, {from_pid, _}, state) do
    ref = make_ref()
    now = System.monotonic_time(:millisecond)
    task = {ref, from_pid, task_func, now}

    cond do
      length(state.idle_workers) > 0 ->
        [worker | rest] = state.idle_workers
        send(worker, {:run, {ref, from_pid, task_func}})

        new_state = %{
          state
          | idle_workers: rest,
            busy_workers: Map.put(state.busy_workers, worker, {ref, from_pid})
        }

        {:reply, {:ok, ref}, new_state}

      total_queue_length(state) < state.max_queue ->
        updated_queues =
          Map.update!(state.queues, priority, fn q -> :queue.in(task, q) end)

        {:reply, {:ok, ref}, %{state | queues: updated_queues}}

      true ->
        {:reply, {:error, :queue_full}, state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      busy_workers: map_size(state.busy_workers),
      idle_workers: length(state.idle_workers),
      queue_high: :queue.len(state.queues.high),
      queue_normal: :queue.len(state.queues.normal),
      queue_low: :queue.len(state.queues.low),
      total_queue_length: total_queue_length(state)
    }

    {:reply, status, state}
  end

  @impl true
  def handle_info({:task_finished, worker, ref, result}, state) do
    case Map.get(state.busy_workers, worker) do
      {^ref, client_pid} ->
        send(client_pid, {ref, :result, result})
        {:noreply, dispatch_next(state, worker)}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, mref, :process, pid, reason}, state) do
    new_monitors = Map.delete(state.monitors, mref)

    state =
      case Map.pop(state.busy_workers, pid) do
        {{ref, client_pid}, updated_busy} ->
          send(client_pid, {ref, :error, {:task_crashed, reason}})
          %{state | busy_workers: updated_busy}

        {nil, _} ->
          %{state | idle_workers: List.delete(state.idle_workers, pid)}
      end

    {:ok, new_pid} = start_worker(state.sup)
    new_mref = Process.monitor(new_pid)

    final_state = %{state | monitors: Map.put(new_monitors, new_mref, new_pid)}
    {:noreply, dispatch_next(final_state, new_pid)}
  end

  @impl true
  def handle_info(:promote_stale_tasks, state) do
    now = System.monotonic_time(:millisecond)
    threshold = state.promote_after_ms

    # Promote low → normal
    {promoted_from_low, remaining_low} =
      partition_stale(state.queues.low, now, threshold)

    # Promote normal → high
    {promoted_from_normal, remaining_normal} =
      partition_stale(state.queues.normal, now, threshold)

    # Merge promoted tasks into their target queues (append to back to keep FIFO among promoted)
    new_normal = enqueue_all(remaining_normal, promoted_from_low)
    new_high = enqueue_all(state.queues.high, promoted_from_normal)

    new_queues = %{high: new_high, normal: new_normal, low: remaining_low}

    schedule_promotion(threshold)
    {:noreply, %{state | queues: new_queues}}
  end

  ## --- Private Helpers ---

  defp start_worker(sup) do
    DynamicSupervisor.start_child(sup, {PriorityWorkerPool.Worker, [self()]})
  end

  defp total_queue_length(state) do
    state.queues
    |> Map.values()
    |> Enum.map(&:queue.len/1)
    |> Enum.sum()
  end

  defp dispatch_next(state, worker) do
    case dequeue_highest(state.queues) do
      {:ok, {ref, client_pid, func, _enqueued_at}, new_queues} ->
        send(worker, {:run, {ref, client_pid, func}})

        %{
          state
          | queues: new_queues,
            busy_workers: Map.put(state.busy_workers, worker, {ref, client_pid})
        }

      :empty ->
        %{
          state
          | idle_workers: [worker | state.idle_workers],
            busy_workers: Map.delete(state.busy_workers, worker)
        }
    end
  end

  defp dequeue_highest(queues) do
    Enum.reduce_while([:high, :normal, :low], :empty, fn priority, _acc ->
      case :queue.out(queues[priority]) do
        {{:value, task}, remaining} ->
          {:halt, {:ok, task, Map.put(queues, priority, remaining)}}

        {:empty, _} ->
          {:cont, :empty}
      end
    end)
  end

  defp partition_stale(queue, now, threshold) do
    list = :queue.to_list(queue)

    {stale, fresh} =
      Enum.split_with(list, fn {_ref, _pid, _func, enqueued_at} ->
        now - enqueued_at >= threshold
      end)

    {stale, :queue.from_list(fresh)}
  end

  defp enqueue_all(queue, items) do
    Enum.reduce(items, queue, fn item, q -> :queue.in(item, q) end)
  end

  defp schedule_promotion(interval_ms) do
    Process.send_after(self(), :promote_stale_tasks, interval_ms)
  end

  ## --- Internal Worker ---

  defmodule Worker do
    @moduledoc false
    use GenServer, restart: :temporary

    def start_link(args), do: GenServer.start_link(__MODULE__, args)

    @impl true
    def init([manager_pid]), do: {:ok, manager_pid}

    @impl true
    def handle_info({:run, {ref, _client_pid, func}}, manager_pid) do
      result = func.()
      send(manager_pid, {:task_finished, self(), ref, result})
      {:noreply, manager_pid}
    end
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule PriorityWorkerPoolTest do
  use ExUnit.Case, async: false

  defp quick_task(value) do
    fn -> value end
  end

  defp slow_task(ms, value) do
    fn ->
      Process.sleep(ms)
      value
    end
  end

  defp blocking_task(gate) do
    fn ->
      send(gate, {:ready, self()})

      receive do
        :proceed -> :done
      end
    end
  end

  defp release(worker_pid) do
    send(worker_pid, :proceed)
  end

  setup do
    pool =
      start_supervised!(
        {PriorityWorkerPool,
         pool_size: 2,
         max_queue: 5,
         promote_after_ms: 500,
         name: :"pool_#{:erlang.unique_integer([:positive])}"}
      )

    %{pool: pool}
  end

  # -------------------------------------------------------
  # Basic submit / await
  # -------------------------------------------------------

  test "submit and await a simple task at default priority", %{pool: pool} do
    {:ok, ref} = PriorityWorkerPool.submit(pool, quick_task(42))
    assert {:ok, 42} = PriorityWorkerPool.await(pool, ref, 1_000)
  end

  test "submit and await tasks at different priorities", %{pool: pool} do
    # TODO
  end

  test "return value of the task function is the await result", %{pool: pool} do
    {:ok, ref} = PriorityWorkerPool.submit(pool, fn -> %{key: "value"} end, :high)
    assert {:ok, %{key: "value"}} = PriorityWorkerPool.await(pool, ref, 1_000)
  end

  # -------------------------------------------------------
  # Priority ordering
  # -------------------------------------------------------

  test "high-priority queued tasks execute before normal and low", %{pool: pool} do
    collector = self()
    gate = self()

    # Block both workers
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Queue tasks in reverse priority order
    {:ok, _} =
      PriorityWorkerPool.submit(
        pool,
        fn ->
          send(collector, {:executed, :low})
          :low
        end,
        :low
      )

    {:ok, _} =
      PriorityWorkerPool.submit(
        pool,
        fn ->
          send(collector, {:executed, :normal})
          :normal
        end,
        :normal
      )

    {:ok, _} =
      PriorityWorkerPool.submit(
        pool,
        fn ->
          send(collector, {:executed, :high})
          :high
        end,
        :high
      )

    # Release one worker at a time
    release(w1)
    assert_receive {:executed, :high}, 1_000

    release(w2)
    assert_receive {:executed, :normal}, 1_000

    # Third task runs on whichever finishes first
    assert_receive {:executed, :low}, 1_000
  end

  test "within same priority, tasks are FIFO", %{pool: pool} do
    collector = self()
    gate = self()

    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Queue three normal tasks
    for i <- 1..3 do
      PriorityWorkerPool.submit(
        pool,
        fn ->
          send(collector, {:executed, i})
          i
        end,
        :normal
      )
    end

    release(w1)
    assert_receive {:executed, 1}, 1_000

    release(w2)
    assert_receive {:executed, 2}, 1_000

    assert_receive {:executed, 3}, 1_000
  end

  # -------------------------------------------------------
  # Queue behavior
  # -------------------------------------------------------

  test "tasks are queued when all workers are busy", %{pool: pool} do
    gate = self()

    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    {:ok, r3} = PriorityWorkerPool.submit(pool, quick_task(:queued_1), :normal)
    {:ok, r4} = PriorityWorkerPool.submit(pool, quick_task(:queued_2), :low)

    status = PriorityWorkerPool.status(pool)
    assert status.busy_workers == 2
    assert status.idle_workers == 0
    assert status.total_queue_length >= 2

    release(w1)
    release(w2)

    assert {:ok, :queued_1} = PriorityWorkerPool.await(pool, r3, 2_000)
    assert {:ok, :queued_2} = PriorityWorkerPool.await(pool, r4, 2_000)
  end

  test "queue rejects when full across all priorities", %{pool: pool} do
    gate = self()

    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Fill the queue (max_queue: 5)
    for _ <- 1..5 do
      {:ok, _} = PriorityWorkerPool.submit(pool, quick_task(:filler), :normal)
    end

    # All priorities should be rejected when queue is full
    assert {:error, :queue_full} = PriorityWorkerPool.submit(pool, quick_task(:overflow), :high)
    assert {:error, :queue_full} = PriorityWorkerPool.submit(pool, quick_task(:overflow), :low)

    release(w1)
    release(w2)
  end

  # -------------------------------------------------------
  # Status introspection
  # -------------------------------------------------------

  test "status reflects pool state accurately", %{pool: pool} do
    status = PriorityWorkerPool.status(pool)
    assert status.idle_workers == 2
    assert status.busy_workers == 0
    assert status.queue_high == 0
    assert status.queue_normal == 0
    assert status.queue_low == 0
    assert status.total_queue_length == 0
  end

  test "status shows per-priority queue counts", %{pool: pool} do
    gate = self()

    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    {:ok, _} = PriorityWorkerPool.submit(pool, quick_task(:h1), :high)
    {:ok, _} = PriorityWorkerPool.submit(pool, quick_task(:n1), :normal)
    {:ok, _} = PriorityWorkerPool.submit(pool, quick_task(:l1), :low)

    status = PriorityWorkerPool.status(pool)
    assert status.queue_high == 1
    assert status.queue_normal == 1
    assert status.queue_low == 1
    assert status.total_queue_length == 3

    release(w1)
    release(w2)
  end

  # -------------------------------------------------------
  # Timeout
  # -------------------------------------------------------

  test "await returns timeout when task takes too long", %{pool: pool} do
    {:ok, ref} = PriorityWorkerPool.submit(pool, slow_task(2_000, :late), :normal)
    assert {:error, :timeout} = PriorityWorkerPool.await(pool, ref, 100)
  end

  # -------------------------------------------------------
  # Starvation prevention
  # -------------------------------------------------------

  test "low-priority tasks are promoted after waiting too long", %{pool: pool} do
    collector = self()
    gate = self()

    # Block both workers
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Enqueue a low-priority task
    {:ok, _} =
      PriorityWorkerPool.submit(
        pool,
        fn ->
          send(collector, {:executed, :promoted_low})
          :promoted_low
        end,
        :low
      )

    # Wait for promotion (promote_after_ms is 500ms in setup)
    Process.sleep(700)

    # Now enqueue a normal-priority task AFTER promotion should have occurred
    {:ok, _} =
      PriorityWorkerPool.submit(
        pool,
        fn ->
          send(collector, {:executed, :fresh_normal})
          :fresh_normal
        end,
        :normal
      )

    # The promoted task (was :low, now :normal or :high) should be in front of
    # or at same level as the fresh normal task
    # Release one worker — the promoted task should run first (it was promoted AND is older)
    release(w1)
    assert_receive {:executed, :promoted_low}, 1_000

    release(w2)
    assert_receive {:executed, :fresh_normal}, 1_000
  end

  test "an aged low task is dispatched before a normal task queued after the promotion",
       %{pool: pool} do
    collector = self()
    gate = self()

    # Occupy both workers so nothing can be dispatched from the queue.
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # This low task blocks once it starts, so a single freed worker can run
    # exactly one queued task and no more.
    {:ok, _} =
      PriorityWorkerPool.submit(
        pool,
        fn ->
          send(collector, {:executed, :aged_low, self()})

          receive do
            :proceed -> :aged_low
          end
        end,
        :low
      )

    # Both workers stay busy while the 500ms promotion interval from setup
    # elapses, so the low task ages in the queue without executing.
    refute_receive {:executed, :aged_low, _}, 900

    # Submitted after the promotion tick, so it is strictly newer than the
    # aged task and sits behind it at the same (promoted) priority level.
    {:ok, _} =
      PriorityWorkerPool.submit(
        pool,
        fn ->
          send(collector, {:executed, :fresh_normal})
          :fresh_normal
        end,
        :normal
      )

    # Free exactly one worker: it must choose the aged, promoted task over the
    # newer normal one. The other worker stays blocked, so a solution that
    # still ranks the task as :low would run :fresh_normal here instead.
    release(w1)

    assert_receive {:executed, :aged_low, aged_worker}, 1_000
    refute_receive {:executed, :fresh_normal}, 300

    release(aged_worker)
    release(w2)
  end

  # -------------------------------------------------------
  # Worker crash recovery
  # -------------------------------------------------------

  test "crash during task returns error to awaiter", %{pool: pool} do
    {:ok, ref} = PriorityWorkerPool.submit(pool, fn -> raise "boom" end, :high)
    assert {:error, {:task_crashed, _reason}} = PriorityWorkerPool.await(pool, ref, 2_000)
  end

  test "pool remains functional after a worker crash", %{pool: pool} do
    {:ok, ref_crash} = PriorityWorkerPool.submit(pool, fn -> raise "kaboom" end)
    PriorityWorkerPool.await(pool, ref_crash, 2_000)

    Process.sleep(100)

    {:ok, ref} = PriorityWorkerPool.submit(pool, quick_task(:after_crash))
    assert {:ok, :after_crash} = PriorityWorkerPool.await(pool, ref, 1_000)
  end

  test "queued tasks are not lost when a worker crashes", %{pool: pool} do
    gate = self()

    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))
    assert_receive {:ready, w1}, 1_000

    {:ok, ref_crash} =
      PriorityWorkerPool.submit(pool, fn ->
        Process.sleep(50)
        raise "crash"
      end)

    {:ok, ref_after} = PriorityWorkerPool.submit(pool, quick_task(:survived), :high)

    assert {:error, {:task_crashed, _}} = PriorityWorkerPool.await(pool, ref_crash, 2_000)

    Process.sleep(200)

    assert {:ok, :survived} = PriorityWorkerPool.await(pool, ref_after, 2_000)

    release(w1)
  end

  test "worker count is restored after crash", %{pool: pool} do
    {:ok, ref} = PriorityWorkerPool.submit(pool, fn -> raise "die" end)
    PriorityWorkerPool.await(pool, ref, 2_000)

    Process.sleep(200)

    status = PriorityWorkerPool.status(pool)
    assert status.idle_workers + status.busy_workers == 2
  end

  # -------------------------------------------------------
  # Defaults
  # -------------------------------------------------------

  test "omitting :pool_size starts three workers", _context do
    name = :"pool_default_size_#{System.pid()}_#{System.unique_integer([:positive])}"
    pool = start_supervised!({PriorityWorkerPool, name: name}, id: :default_size)

    status = PriorityWorkerPool.status(pool)
    assert status.idle_workers == 3
    assert status.busy_workers == 0
    assert status.total_queue_length == 0
  end

  test "omitting :max_queue allows ten pending tasks and rejects the eleventh", _context do
    name = :"pool_default_queue_#{System.pid()}_#{System.unique_integer([:positive])}"
    pool = start_supervised!({PriorityWorkerPool, name: name}, id: :default_queue)

    gate = self()

    # With the default pool of three workers, three blocking tasks leave the
    # pool fully busy so every further submission has to be queued.
    blocked =
      for _ <- 1..3 do
        {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))
        assert_receive {:ready, worker}, 1_000
        worker
      end

    for _ <- 1..10 do
      {:ok, _} = PriorityWorkerPool.submit(pool, quick_task(:filler), :normal)
    end

    assert PriorityWorkerPool.status(pool).total_queue_length == 10
    assert {:error, :queue_full} = PriorityWorkerPool.submit(pool, quick_task(:over), :high)

    Enum.each(blocked, &release/1)
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "pool_size of 1 works correctly", _context do
    pool =
      start_supervised!(
        {PriorityWorkerPool,
         pool_size: 1, max_queue: 2, promote_after_ms: 60_000, name: :single_priority_pool},
        id: :single
      )

    {:ok, r1} = PriorityWorkerPool.submit(pool, quick_task(:only), :low)
    assert {:ok, :only} = PriorityWorkerPool.await(pool, r1, 1_000)
  end

  test "max_queue of 0 means no queuing", _context do
    pool =
      start_supervised!(
        {PriorityWorkerPool,
         pool_size: 1, max_queue: 0, promote_after_ms: 60_000, name: :no_queue_priority_pool},
        id: :no_queue
      )

    gate = self()

    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))
    assert_receive {:ready, w1}, 1_000

    assert {:error, :queue_full} = PriorityWorkerPool.submit(pool, quick_task(:nope), :high)

    release(w1)
  end

  test "await with an unknown ref times out", %{pool: pool} do
    bogus_ref = make_ref()
    assert {:error, _} = PriorityWorkerPool.await(pool, bogus_ref, 200)
  end

  test "an aged normal task outranks a high task queued after its promotion", %{pool: pool} do
    collector = self()
    gate = self()

    # Occupy both workers so nothing dispatches straight from the queue.
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # This normal task blocks once running, so a single freed worker runs
    # exactly one queued task and no more.
    {:ok, _} =
      PriorityWorkerPool.submit(
        pool,
        fn ->
          send(collector, {:executed, :aged_normal, self()})

          receive do
            :proceed -> :aged_normal
          end
        end,
        :normal
      )

    # Age it past the 500ms promotion interval while both workers stay busy, so
    # the normal → high promotion fires without the task ever executing.
    refute_receive {:executed, :aged_normal, _}, 900

    # Submitted after the promotion tick, so it enters the high queue strictly
    # behind the aged task (which should now be high too).
    {:ok, _} =
      PriorityWorkerPool.submit(
        pool,
        fn ->
          send(collector, {:executed, :fresh_high})
          :fresh_high
        end,
        :high
      )

    # Free exactly one worker: it must pick the aged, promoted-to-high task over
    # the newer high one. A solution that left the task at :normal would run
    # :fresh_high first here instead.
    release(w1)

    assert_receive {:executed, :aged_normal, aged_worker}, 1_000
    refute_receive {:executed, :fresh_high}, 300

    release(aged_worker)
    release(w2)
  end

  test "a low task dispatches immediately when a worker is idle instead of queuing", %{pool: pool} do
    gate = self()

    # A :low task with idle workers present must be dispatched, not queued.
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate), :low)

    assert_receive {:ready, worker}, 1_000

    status = PriorityWorkerPool.status(pool)
    assert status.busy_workers == 1
    assert status.queue_low == 0
    assert status.total_queue_length == 0

    release(worker)
  end

  test "each successful submit returns a distinct ref", %{pool: pool} do
    {:ok, r1} = PriorityWorkerPool.submit(pool, quick_task(:a), :normal)
    {:ok, r2} = PriorityWorkerPool.submit(pool, quick_task(:b), :normal)

    assert is_reference(r1)
    assert is_reference(r2)
    assert r1 != r2
  end
end
```
