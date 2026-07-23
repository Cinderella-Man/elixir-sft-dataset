# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

```elixir
defmodule CancellablePool do
  @moduledoc """
  A bounded-queue worker pool with task cancellation support.
  """

  use GenServer

  ## --- Public API ---

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Submits `task_func` to the pool. Returns `{:ok, ref}` or `{:error, :queue_full}`."
  @spec submit(GenServer.server(), (-> any())) :: {:ok, reference()} | {:error, :queue_full}
  def submit(pool, task_func) when is_function(task_func, 0) do
    GenServer.call(pool, {:submit, task_func})
  end

  @spec cancel(GenServer.server(), reference()) :: :ok | {:error, :not_found}
  def cancel(pool, ref) when is_reference(ref) do
    GenServer.call(pool, {:cancel, ref})
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
      queue: :queue.new(),
      idle_workers: [],
      # %{worker_pid => {ref, client_pid}}
      busy_workers: %{},
      # %{monitor_ref => worker_pid}
      monitors: %{},
      # %{ref => client_pid} — tracks refs still in the queue
      pending_refs: %{},
      # refs cancelled while running (to distinguish from a crash)
      cancelled_refs: MapSet.new(),
      cancelled_count: 0
    ]
  end

  @impl true
  def init(opts) do
    pool_size = Keyword.get(opts, :pool_size, 3)
    max_queue = Keyword.get(opts, :max_queue, 10)

    {:ok, sup} = DynamicSupervisor.start_link(strategy: :one_for_one)

    state = %State{
      sup: sup,
      pool_size: pool_size,
      max_queue: max_queue
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

    {:ok, new_state}
  end

  @impl true
  def handle_call({:submit, task_func}, {from_pid, _}, state) do
    ref = make_ref()
    task = {ref, from_pid, task_func}

    cond do
      length(state.idle_workers) > 0 ->
        [worker | rest] = state.idle_workers
        send(worker, {:run, task})

        new_state = %{
          state
          | idle_workers: rest,
            busy_workers: Map.put(state.busy_workers, worker, {ref, from_pid})
        }

        {:reply, {:ok, ref}, new_state}

      :queue.len(state.queue) < state.max_queue ->
        new_state = %{
          state
          | queue: :queue.in(task, state.queue),
            pending_refs: Map.put(state.pending_refs, ref, from_pid)
        }

        {:reply, {:ok, ref}, new_state}

      true ->
        {:reply, {:error, :queue_full}, state}
    end
  end

  @impl true
  def handle_call({:cancel, ref}, _from, state) do
    # Case 1: Task is in the queue (pending)
    case Map.pop(state.pending_refs, ref) do
      {client_pid, remaining_pending} when not is_nil(client_pid) ->
        new_queue = queue_remove(state.queue, ref)
        send(client_pid, {ref, :error, :cancelled})

        new_state = %{
          state
          | queue: new_queue,
            pending_refs: remaining_pending,
            cancelled_count: state.cancelled_count + 1
        }

        {:reply, :ok, new_state}

      {nil, _} ->
        # Case 2: Task is currently running on a worker
        case find_busy_worker(state.busy_workers, ref) do
          {worker_pid, {^ref, client_pid}} ->
            # Mark this ref as cancelled so the :DOWN handler knows
            new_cancelled = MapSet.put(state.cancelled_refs, ref)
            # Kill the worker — this will trigger :DOWN
            Process.exit(worker_pid, :kill)

            # Send cancelled message to the client
            send(client_pid, {ref, :error, :cancelled})

            new_state = %{
              state
              | cancelled_refs: new_cancelled,
                cancelled_count: state.cancelled_count + 1
            }

            {:reply, :ok, new_state}

          nil ->
            # Case 3: Unknown ref
            {:reply, {:error, :not_found}, state}
        end
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      busy_workers: map_size(state.busy_workers),
      idle_workers: length(state.idle_workers),
      queue_length: :queue.len(state.queue),
      cancelled_count: state.cancelled_count
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
          was_cancelled = MapSet.member?(state.cancelled_refs, ref)

          if was_cancelled do
            # Already sent :cancelled in the cancel handler, just clean up
            %{
              state
              | busy_workers: updated_busy,
                cancelled_refs: MapSet.delete(state.cancelled_refs, ref)
            }
          else
            # Genuine crash — notify client
            send(client_pid, {ref, :error, {:task_crashed, reason}})
            %{state | busy_workers: updated_busy}
          end

        {nil, _} ->
          %{state | idle_workers: List.delete(state.idle_workers, pid)}
      end

    # Replace the dead worker
    {:ok, new_pid} = start_worker(state.sup)
    new_mref = Process.monitor(new_pid)

    final_state = %{state | monitors: Map.put(new_monitors, new_mref, new_pid)}
    {:noreply, dispatch_next(final_state, new_pid)}
  end

  ## --- Private Helpers ---

  defp start_worker(sup) do
    DynamicSupervisor.start_child(sup, {CancellablePool.Worker, [self()]})
  end

  defp dispatch_next(state, worker) do
    case :queue.out(state.queue) do
      {{:value, {ref, client_pid, func}}, remaining_queue} ->
        send(worker, {:run, {ref, client_pid, func}})

        %{
          state
          | queue: remaining_queue,
            busy_workers: Map.put(state.busy_workers, worker, {ref, client_pid}),
            pending_refs: Map.delete(state.pending_refs, ref)
        }

      {:empty, _} ->
        %{
          state
          | idle_workers: [worker | state.idle_workers],
            busy_workers: Map.delete(state.busy_workers, worker)
        }
    end
  end

  defp queue_remove(queue, target_ref) do
    queue
    |> :queue.to_list()
    |> Enum.reject(fn {ref, _pid, _func} -> ref == target_ref end)
    |> :queue.from_list()
  end

  defp find_busy_worker(busy_workers, target_ref) do
    Enum.find(busy_workers, fn {_pid, {ref, _client}} -> ref == target_ref end)
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
defmodule CancellablePoolTest do
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

  # Announces itself under a distinct tag, then raises once released, so a
  # crash can be triggered at a precise moment while other work is pending.
  defp crash_on_signal(gate) do
    fn ->
      send(gate, {:crash_ready, self()})

      receive do
        :proceed -> raise "boom"
      end
    end
  end

  defp unique_name(prefix) do
    :"#{prefix}_#{System.pid()}_#{System.unique_integer([:positive])}"
  end

  setup do
    pool =
      start_supervised!(
        {CancellablePool,
         pool_size: 2, max_queue: 3, name: :"pool_#{:erlang.unique_integer([:positive])}"}
      )

    %{pool: pool}
  end

  # -------------------------------------------------------
  # Basic submit / await
  # -------------------------------------------------------

  test "submit and await a simple task", %{pool: pool} do
    {:ok, ref} = CancellablePool.submit(pool, quick_task(42))
    assert {:ok, 42} = CancellablePool.await(pool, ref, 1_000)
  end

  test "submit and await multiple tasks", %{pool: pool} do
    {:ok, r1} = CancellablePool.submit(pool, quick_task(:a))
    {:ok, r2} = CancellablePool.submit(pool, quick_task(:b))
    {:ok, r3} = CancellablePool.submit(pool, quick_task(:c))

    assert {:ok, :a} = CancellablePool.await(pool, r1, 1_000)
    assert {:ok, :b} = CancellablePool.await(pool, r2, 1_000)
    assert {:ok, :c} = CancellablePool.await(pool, r3, 1_000)
  end

  # -------------------------------------------------------
  # Cancel a pending (queued) task
  # -------------------------------------------------------

  test "cancel a pending task removes it from queue", %{pool: pool} do
    gate = self()

    # Block both workers
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Enqueue a task
    {:ok, ref_pending} = CancellablePool.submit(pool, quick_task(:should_cancel))

    # Cancel it
    assert :ok = CancellablePool.cancel(pool, ref_pending)

    # Awaiter gets :cancelled
    assert {:error, :cancelled} = CancellablePool.await(pool, ref_pending, 1_000)

    # Queue should now be empty
    status = CancellablePool.status(pool)
    assert status.queue_length == 0

    release(w1)
    release(w2)
  end

  test "cancelling a pending task frees a queue slot", %{pool: pool} do
    gate = self()

    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Fill the queue (max_queue: 3)
    {:ok, _} = CancellablePool.submit(pool, quick_task(:q1))
    {:ok, _} = CancellablePool.submit(pool, quick_task(:q2))
    {:ok, ref_q3} = CancellablePool.submit(pool, quick_task(:q3))

    # Queue is full
    assert {:error, :queue_full} = CancellablePool.submit(pool, quick_task(:overflow))

    # Cancel one queued task
    assert :ok = CancellablePool.cancel(pool, ref_q3)

    # Now there's room
    {:ok, _} = CancellablePool.submit(pool, quick_task(:fits_now))

    release(w1)
    release(w2)
  end

  # -------------------------------------------------------
  # Cancel a running task
  # -------------------------------------------------------

  test "cancel a running task kills the worker and notifies awaiter", %{pool: pool} do
    gate = self()

    {:ok, ref_running} = CancellablePool.submit(pool, blocking_task(gate))
    assert_receive {:ready, _w1}, 1_000

    # Cancel the running task
    assert :ok = CancellablePool.cancel(pool, ref_running)

    # Awaiter receives :cancelled
    assert {:error, :cancelled} = CancellablePool.await(pool, ref_running, 1_000)
  end

  test "cancelling a running task frees a worker for queued work", %{pool: pool} do
    gate = self()

    # Fill both workers
    {:ok, ref_to_cancel} = CancellablePool.submit(pool, blocking_task(gate))
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))

    assert_receive {:ready, _w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Queue a task
    {:ok, ref_queued} = CancellablePool.submit(pool, quick_task(:from_queue))

    # Cancel the first running task — replacement should grab queued task
    assert :ok = CancellablePool.cancel(pool, ref_to_cancel)

    # The queued task should complete on the replacement worker
    assert {:ok, :from_queue} = CancellablePool.await(pool, ref_queued, 2_000)

    release(w2)
  end

  # -------------------------------------------------------
  # Cancel unknown ref
  # -------------------------------------------------------

  test "cancel an unknown ref returns not_found", %{pool: pool} do
    bogus_ref = make_ref()
    assert {:error, :not_found} = CancellablePool.cancel(pool, bogus_ref)
  end

  test "cancel an already-completed task returns not_found", %{pool: pool} do
    {:ok, ref} = CancellablePool.submit(pool, quick_task(:done))
    assert {:ok, :done} = CancellablePool.await(pool, ref, 1_000)

    # Try to cancel after completion
    assert {:error, :not_found} = CancellablePool.cancel(pool, ref)
  end

  test "double cancel returns not_found on second attempt", %{pool: pool} do
    gate = self()

    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    {:ok, ref} = CancellablePool.submit(pool, quick_task(:target))

    assert :ok = CancellablePool.cancel(pool, ref)
    assert {:error, :not_found} = CancellablePool.cancel(pool, ref)

    release(w1)
    release(w2)
  end

  # -------------------------------------------------------
  # Status / cancelled_count
  # -------------------------------------------------------

  test "cancelled_count increments on each cancellation", %{pool: pool} do
    gate = self()

    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    {:ok, r1} = CancellablePool.submit(pool, quick_task(:c1))
    {:ok, r2} = CancellablePool.submit(pool, quick_task(:c2))

    CancellablePool.cancel(pool, r1)
    CancellablePool.cancel(pool, r2)

    status = CancellablePool.status(pool)
    assert status.cancelled_count == 2

    release(w1)
    release(w2)
  end

  # -------------------------------------------------------
  # Queue behavior (same as original)
  # -------------------------------------------------------

  test "queue rejects when full", %{pool: pool} do
    gate = self()

    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    {:ok, _} = CancellablePool.submit(pool, quick_task(:q1))
    {:ok, _} = CancellablePool.submit(pool, quick_task(:q2))
    {:ok, _} = CancellablePool.submit(pool, quick_task(:q3))

    assert {:error, :queue_full} = CancellablePool.submit(pool, quick_task(:overflow))

    release(w1)
    release(w2)
  end

  test "queued tasks execute in FIFO order", %{pool: pool} do
    collector = self()
    gate = self()

    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    for i <- 1..3 do
      CancellablePool.submit(pool, fn ->
        send(collector, {:executed, i})
        i
      end)
    end

    release(w1)
    assert_receive {:executed, 1}, 1_000

    release(w2)
    assert_receive {:executed, 2}, 1_000

    assert_receive {:executed, 3}, 1_000
  end

  # -------------------------------------------------------
  # Worker crash recovery (non-cancellation crashes)
  # -------------------------------------------------------

  test "crash during task returns task_crashed to awaiter", %{pool: pool} do
    {:ok, ref} = CancellablePool.submit(pool, fn -> raise "boom" end)
    assert {:error, {:task_crashed, _reason}} = CancellablePool.await(pool, ref, 2_000)
  end

  test "pool remains functional after a worker crash", %{pool: pool} do
    # TODO
  end

  test "worker count is restored after crash", %{pool: pool} do
    {:ok, ref} = CancellablePool.submit(pool, fn -> raise "die" end)
    CancellablePool.await(pool, ref, 2_000)

    Process.sleep(200)

    status = CancellablePool.status(pool)
    assert status.idle_workers + status.busy_workers == 2
  end

  # A crash with work still pending must not strand the queue: the replacement
  # worker has to pick up the queued task, and the rest of the queue must drain
  # as the other workers free up.
  test "queued tasks survive a worker crash and still run in order", %{pool: pool} do
    gate = self()
    collector = self()

    {:ok, ref_crash} = CancellablePool.submit(pool, crash_on_signal(gate))
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))

    assert_receive {:crash_ready, crashing_worker}, 1_000
    assert_receive {:ready, blocked_worker}, 1_000

    {:ok, ref_q1} = CancellablePool.submit(pool, fn -> send(collector, {:ran, 1}) && :q1 end)
    {:ok, ref_q2} = CancellablePool.submit(pool, fn -> send(collector, {:ran, 2}) && :q2 end)

    # Crash the worker while both tasks are still waiting in the queue.
    release(crashing_worker)

    assert {:error, {:task_crashed, _reason}} = CancellablePool.await(pool, ref_crash, 2_000)

    # The replacement worker must take the head of the queue.
    assert {:ok, :q1} = CancellablePool.await(pool, ref_q1, 2_000)
    assert_receive {:ran, 1}, 2_000

    # The remaining queued task runs once the other worker frees up.
    release(blocked_worker)
    assert {:ok, :q2} = CancellablePool.await(pool, ref_q2, 2_000)
    assert_receive {:ran, 2}, 2_000

    assert CancellablePool.status(pool).queue_length == 0
  end

  # -------------------------------------------------------
  # Timeout
  # -------------------------------------------------------

  test "await returns timeout when task takes too long", %{pool: pool} do
    {:ok, ref} = CancellablePool.submit(pool, slow_task(2_000, :late))
    assert {:error, :timeout} = CancellablePool.await(pool, ref, 100)
  end

  # -------------------------------------------------------
  # Default options
  # -------------------------------------------------------

  test "pool started without options has 3 idle workers and an empty queue", _context do
    pool =
      start_supervised!({CancellablePool, name: unique_name(:default_pool)}, id: :defaults)

    status = CancellablePool.status(pool)

    assert status.idle_workers == 3
    assert status.busy_workers == 0
    assert status.queue_length == 0
    assert status.cancelled_count == 0
  end

  test "pool started without options queues 10 tasks before rejecting", _context do
    gate = self()

    pool =
      start_supervised!({CancellablePool, name: unique_name(:default_queue_pool)},
        id: :default_queue
      )

    # Occupy all three default workers.
    for _ <- 1..3 do
      {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))
    end

    workers =
      for _ <- 1..3 do
        assert_receive {:ready, worker}, 1_000
        worker
      end

    # The default queue holds exactly 10 pending tasks.
    for i <- 1..10 do
      assert {:ok, _ref} = CancellablePool.submit(pool, quick_task(i))
    end

    assert CancellablePool.status(pool).queue_length == 10
    assert {:error, :queue_full} = CancellablePool.submit(pool, quick_task(:overflow))

    Enum.each(workers, &release/1)
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "pool_size of 1 works correctly", _context do
    pool =
      start_supervised!(
        {CancellablePool, pool_size: 1, max_queue: 2, name: :single_cancel_pool},
        id: :single
      )

    {:ok, r1} = CancellablePool.submit(pool, quick_task(:only))
    assert {:ok, :only} = CancellablePool.await(pool, r1, 1_000)
  end

  test "await with an unknown ref returns timeout", %{pool: pool} do
    bogus_ref = make_ref()
    assert {:error, _} = CancellablePool.await(pool, bogus_ref, 200)
  end

  # An unknown ref is not resolved early: await has to block for the whole
  # timeout window and then report exactly :timeout, never an immediate
  # lookup failure such as :not_found.
  test "await on an unknown ref blocks the full timeout then reports timeout",
       %{pool: pool} do
    bogus_ref = make_ref()
    started = System.monotonic_time(:millisecond)

    assert {:error, :timeout} = CancellablePool.await(pool, bogus_ref, 400)

    elapsed = System.monotonic_time(:millisecond) - started
    assert elapsed >= 350
  end

  test "cancelling a queued task prevents that task from ever executing", %{pool: pool} do
    gate = self()
    me = self()

    # Occupy both workers so the next submission is queued, not dispatched.
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Enqueue a task with an observable side effect, then cancel it while queued.
    {:ok, ref} =
      CancellablePool.submit(pool, fn ->
        send(me, :sneaky_ran)
        :sneaky
      end)

    assert :ok = CancellablePool.cancel(pool, ref)

    # Free both workers so the queue would drain if the task were still present.
    release(w1)
    release(w2)

    # A fresh task proves the pool has cycled through a dispatch pass.
    {:ok, probe} = CancellablePool.submit(pool, quick_task(:probe))
    assert {:ok, :probe} = CancellablePool.await(pool, probe, 1_000)

    # The cancelled task must never have run.
    refute_receive :sneaky_ran, 300
  end

  test "queue keeps FIFO order after a middle task is cancelled", %{pool: pool} do
    gate = self()
    collector = self()

    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Fill the queue (max_queue: 3) with three ordered tasks.
    {:ok, _q1} = CancellablePool.submit(pool, fn -> send(collector, {:ran, 1}) && 1 end)
    {:ok, q2} = CancellablePool.submit(pool, fn -> send(collector, {:ran, 2}) && 2 end)
    {:ok, _q3} = CancellablePool.submit(pool, fn -> send(collector, {:ran, 3}) && 3 end)

    # Cancel the middle task; the survivors must still run in submission order.
    assert :ok = CancellablePool.cancel(pool, q2)

    release(w1)
    assert_receive {:ran, 1}, 1_000

    release(w2)
    assert_receive {:ran, 3}, 1_000

    # The cancelled middle task must never execute.
    refute_receive {:ran, 2}, 300
  end

  test "cancelling a running task increments cancelled_count", %{pool: pool} do
    {:ok, ref} = CancellablePool.submit(pool, blocking_task(self()))
    assert_receive {:ready, _w}, 1_000

    assert :ok = CancellablePool.cancel(pool, ref)
    assert {:error, :cancelled} = CancellablePool.await(pool, ref, 1_000)

    assert CancellablePool.status(pool).cancelled_count == 1
  end
end
```
