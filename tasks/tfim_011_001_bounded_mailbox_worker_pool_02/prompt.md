# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule WorkerPool do
  @moduledoc """
  A bounded-queue worker pool implementation using GenServer and DynamicSupervisor.
  """

  use GenServer

  ## --- Public API ---

  @doc "Starts the worker pool with given options."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Submits a zero-arity function to the pool for execution."
  @spec submit(GenServer.server(), (-> any())) :: {:ok, reference()} | {:error, :queue_full}
  def submit(pool, task_func) when is_function(task_func, 0) do
    GenServer.call(pool, {:submit, task_func})
  end

  @doc "Awaits the result of a submitted task by its reference."
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

  @doc "Returns the current status of the pool."
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
      queue: :queue.new(),
      idle_workers: [],
      # %{worker_pid => {ref, client_pid}}
      busy_workers: %{},
      # %{monitor_ref => worker_pid}
      monitors: %{}
    ]
  end

  @impl true
  def init(opts) do
    pool_size = Keyword.get(opts, :pool_size, 3)
    max_queue = Keyword.get(opts, :max_queue, 10)

    # Start a DynamicSupervisor to manage the workers
    {:ok, sup} = DynamicSupervisor.start_link(strategy: :one_for_one)

    state = %State{
      sup: sup,
      pool_size: pool_size,
      max_queue: max_queue
    }

    # Initialize the worker pool
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

    {:ok, new_state}
  end

  @impl true
  def handle_call({:submit, task_func}, {from_pid, _}, state) do
    ref = make_ref()
    task = {ref, from_pid, task_func}

    cond do
      # Case 1: Instant dispatch to idle worker
      length(state.idle_workers) > 0 ->
        [worker | rest] = state.idle_workers
        send(worker, {:run, task})

        new_state = %{
          state
          | idle_workers: rest,
            busy_workers: Map.put(state.busy_workers, worker, {ref, from_pid})
        }

        {:reply, {:ok, ref}, new_state}

      # Case 2: Enqueue if there is room
      :queue.len(state.queue) < state.max_queue ->
        new_state = %{state | queue: :queue.in(task, state.queue)}
        {:reply, {:ok, ref}, new_state}

      # Case 3: Queue full
      true ->
        {:reply, {:error, :queue_full}, state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      busy_workers: map_size(state.busy_workers),
      idle_workers: length(state.idle_workers),
      queue_length: :queue.len(state.queue)
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

    # If the worker was busy, notify the client it crashed
    state =
      case Map.pop(state.busy_workers, pid) do
        {{ref, client_pid}, updated_busy} ->
          send(client_pid, {ref, :error, {:task_crashed, reason}})
          %{state | busy_workers: updated_busy}

        {nil, _} ->
          %{state | idle_workers: List.delete(state.idle_workers, pid)}
      end

    # Replace the crashed worker
    {:ok, new_worker_pid} = start_worker(state.sup)
    new_mref = Process.monitor(new_worker_pid)

    final_state = %{state | monitors: Map.put(new_monitors, new_mref, new_worker_pid)}

    # Immediately try to give the new worker a task from the queue
    {:noreply, dispatch_next(final_state, new_worker_pid)}
  end

  ## --- Private Helpers ---

  defp start_worker(sup) do
    DynamicSupervisor.start_child(sup, {WorkerPool.Worker, [self()]})
  end

  defp dispatch_next(state, worker) do
    case :queue.out(state.queue) do
      {{:value, {ref, client_pid, func}}, remaining_queue} ->
        send(worker, {:run, {ref, client_pid, func}})

        %{
          state
          | queue: remaining_queue,
            busy_workers: Map.put(state.busy_workers, worker, {ref, client_pid})
        }

      {:empty, _} ->
        %{
          state
          | idle_workers: [worker | state.idle_workers],
            busy_workers: Map.delete(state.busy_workers, worker)
        }
    end
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
defmodule WorkerPoolTest do
  use ExUnit.Case, async: false

  # Helper: a task that takes a controllable amount of time
  # We use message passing to synchronize instead of real sleeps.

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
        {WorkerPool,
         pool_size: 2, max_queue: 3, name: :"pool_#{:erlang.unique_integer([:positive])}"}
      )

    %{pool: pool}
  end

  # -------------------------------------------------------
  # Basic submit / await
  # -------------------------------------------------------

  test "submit and await a simple task", %{pool: pool} do
    # TODO
  end

  test "submit and await multiple tasks", %{pool: pool} do
    {:ok, r1} = WorkerPool.submit(pool, quick_task(:a))
    {:ok, r2} = WorkerPool.submit(pool, quick_task(:b))
    {:ok, r3} = WorkerPool.submit(pool, quick_task(:c))

    assert {:ok, :a} = WorkerPool.await(pool, r1, 1_000)
    assert {:ok, :b} = WorkerPool.await(pool, r2, 1_000)
    assert {:ok, :c} = WorkerPool.await(pool, r3, 1_000)
  end

  test "return value of the task function is the await result", %{pool: pool} do
    {:ok, ref} = WorkerPool.submit(pool, fn -> %{key: "value", num: 123} end)
    assert {:ok, %{key: "value", num: 123}} = WorkerPool.await(pool, ref, 1_000)
  end

  # -------------------------------------------------------
  # Queue behavior
  # -------------------------------------------------------

  test "tasks are queued when all workers are busy", %{pool: pool} do
    gate = self()

    # Fill both workers with blocking tasks
    {:ok, _r1} = WorkerPool.submit(pool, blocking_task(gate))
    {:ok, _r2} = WorkerPool.submit(pool, blocking_task(gate))

    # Wait for both workers to be running
    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # These should be queued (not rejected)
    {:ok, r3} = WorkerPool.submit(pool, quick_task(:queued_1))
    {:ok, r4} = WorkerPool.submit(pool, quick_task(:queued_2))

    # Verify queue status
    status = WorkerPool.status(pool)
    assert status.busy_workers == 2
    assert status.idle_workers == 0
    assert status.queue_length >= 2

    # Release workers so queued tasks execute
    release(w1)
    release(w2)

    assert {:ok, :queued_1} = WorkerPool.await(pool, r3, 2_000)
    assert {:ok, :queued_2} = WorkerPool.await(pool, r4, 2_000)
  end

  test "queue rejects when full", %{pool: pool} do
    gate = self()

    # Fill 2 workers
    {:ok, _} = WorkerPool.submit(pool, blocking_task(gate))
    {:ok, _} = WorkerPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Fill the queue (max_queue: 3)
    {:ok, _} = WorkerPool.submit(pool, quick_task(:q1))
    {:ok, _} = WorkerPool.submit(pool, quick_task(:q2))
    {:ok, _} = WorkerPool.submit(pool, quick_task(:q3))

    # This should be rejected
    assert {:error, :queue_full} = WorkerPool.submit(pool, quick_task(:overflow))

    # Cleanup
    release(w1)
    release(w2)
  end

  # -------------------------------------------------------
  # FIFO ordering
  # -------------------------------------------------------

  test "queued tasks execute in FIFO order", %{pool: pool} do
    collector = self()
    gate = self()

    # Block the single-ish pool — use pool_size: 1 for clearer ordering
    # We'll use the 2-worker pool but block both workers first
    {:ok, _} = WorkerPool.submit(pool, blocking_task(gate))
    {:ok, _} = WorkerPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Queue tasks that report their execution order
    for i <- 1..3 do
      WorkerPool.submit(pool, fn ->
        send(collector, {:executed, i})
        i
      end)
    end

    # Release one worker at a time to force serial execution
    release(w1)
    assert_receive {:executed, 1}, 1_000

    release(w2)
    assert_receive {:executed, 2}, 1_000

    # Third task runs on whichever worker finishes first
    assert_receive {:executed, 3}, 1_000
  end

  # -------------------------------------------------------
  # Timeout
  # -------------------------------------------------------

  test "await returns timeout when task takes too long", %{pool: pool} do
    {:ok, ref} = WorkerPool.submit(pool, slow_task(2_000, :late))
    assert {:error, :timeout} = WorkerPool.await(pool, ref, 100)
  end

  # -------------------------------------------------------
  # Status introspection
  # -------------------------------------------------------

  test "status reflects pool state accurately", %{pool: pool} do
    # Initially all idle
    status = WorkerPool.status(pool)
    assert status.idle_workers == 2
    assert status.busy_workers == 0
    assert status.queue_length == 0
  end

  test "status updates as tasks are submitted", %{pool: pool} do
    gate = self()

    {:ok, _} = WorkerPool.submit(pool, blocking_task(gate))
    assert_receive {:ready, w1}, 1_000

    status = WorkerPool.status(pool)
    assert status.busy_workers == 1
    assert status.idle_workers == 1
    assert status.queue_length == 0

    release(w1)
  end

  # -------------------------------------------------------
  # Worker crash recovery
  # -------------------------------------------------------

  test "crash during task returns error to awaiter", %{pool: pool} do
    {:ok, ref} = WorkerPool.submit(pool, fn -> raise "boom" end)

    assert {:error, {:task_crashed, _reason}} = WorkerPool.await(pool, ref, 2_000)
  end

  test "pool remains functional after a worker crash", %{pool: pool} do
    # Submit a crashing task
    {:ok, ref_crash} = WorkerPool.submit(pool, fn -> raise "kaboom" end)
    WorkerPool.await(pool, ref_crash, 2_000)

    # Give the pool a moment to recover / restart the worker
    Process.sleep(100)

    # Pool should still work
    {:ok, ref} = WorkerPool.submit(pool, quick_task(:after_crash))
    assert {:ok, :after_crash} = WorkerPool.await(pool, ref, 1_000)
  end

  test "queued tasks are not lost when a worker crashes", %{pool: pool} do
    gate = self()

    # Block worker 1 with a normal task
    {:ok, _} = WorkerPool.submit(pool, blocking_task(gate))
    assert_receive {:ready, w1}, 1_000

    # Worker 2 gets the crashing task
    {:ok, ref_crash} =
      WorkerPool.submit(pool, fn ->
        Process.sleep(50)
        raise "crash"
      end)

    # Queue a task behind the crash
    {:ok, ref_after} = WorkerPool.submit(pool, quick_task(:survived))

    # The crash task should fail
    assert {:error, {:task_crashed, _}} = WorkerPool.await(pool, ref_crash, 2_000)

    # Give pool time to restart worker and dequeue
    Process.sleep(200)

    # The queued task should still complete
    assert {:ok, :survived} = WorkerPool.await(pool, ref_after, 2_000)

    # Cleanup
    release(w1)
  end

  test "worker count is restored after crash", %{pool: pool} do
    # Crash a worker
    {:ok, ref} = WorkerPool.submit(pool, fn -> raise "die" end)
    WorkerPool.await(pool, ref, 2_000)

    # Give supervisor time to restart
    Process.sleep(200)

    status = WorkerPool.status(pool)
    assert status.idle_workers + status.busy_workers == 2
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "pool_size of 1 works correctly", _context do
    pool =
      start_supervised!(
        {WorkerPool, pool_size: 1, max_queue: 2, name: :single_worker_pool},
        id: :single
      )

    {:ok, r1} = WorkerPool.submit(pool, quick_task(:only))
    assert {:ok, :only} = WorkerPool.await(pool, r1, 1_000)
  end

  test "max_queue of 0 means no queuing — reject immediately when busy", _context do
    pool =
      start_supervised!(
        {WorkerPool, pool_size: 1, max_queue: 0, name: :no_queue_pool},
        id: :no_queue
      )

    gate = self()

    {:ok, _} = WorkerPool.submit(pool, blocking_task(gate))
    assert_receive {:ready, w1}, 1_000

    # Worker is busy, queue is 0 → reject
    assert {:error, :queue_full} = WorkerPool.submit(pool, quick_task(:nope))

    release(w1)
  end

  test "await with an unknown ref returns an error or times out", %{pool: pool} do
    bogus_ref = make_ref()
    assert {:error, _} = WorkerPool.await(pool, bogus_ref, 200)
  end

  test "submitting many tasks beyond pool+queue capacity", %{pool: pool} do
    gate = self()

    # Block both workers
    {:ok, _} = WorkerPool.submit(pool, blocking_task(gate))
    {:ok, _} = WorkerPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Fill queue (3 slots)
    results =
      for i <- 1..5 do
        WorkerPool.submit(pool, quick_task(i))
      end

    ok_count = Enum.count(results, &match?({:ok, _}, &1))
    err_count = Enum.count(results, &match?({:error, :queue_full}, &1))

    assert ok_count == 3
    assert err_count == 2

    release(w1)
    release(w2)
  end
end
```
