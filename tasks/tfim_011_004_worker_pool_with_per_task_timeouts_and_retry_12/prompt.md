# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule RetryPool do
  @moduledoc """
  A bounded-queue worker pool with per-task execution timeouts and automatic retry.
  """

  use GenServer

  ## --- Public API ---

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Submits `task_func` with a per-task timeout and retry policy from `opts`. Returns
  `{:ok, ref}`; await the result with `await/3`.
  """
  @spec submit(GenServer.server(), (-> any()), keyword()) ::
          {:ok, reference()} | {:error, :queue_full}
  def submit(pool, task_func, opts \\ []) when is_function(task_func, 0) do
    GenServer.call(pool, {:submit, task_func, opts})
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

  defmodule TaskInfo do
    @moduledoc false
    defstruct [
      :ref,
      :client_pid,
      :func,
      :task_timeout,
      :max_retries,
      attempts: 0
    ]
  end

  defmodule State do
    defstruct [
      :sup,
      :max_queue,
      :pool_size,
      queue: :queue.new(),
      idle_workers: [],
      # %{worker_pid => %TaskInfo{}}
      busy_workers: %{},
      # %{monitor_ref => worker_pid}
      monitors: %{},
      # %{worker_pid => timer_ref}
      worker_timers: %{},
      retry_count: 0
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
      Enum.reduce(1..pool_size//1, state, fn _, acc ->
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
  def handle_call({:submit, task_func, opts}, {from_pid, _}, state) do
    ref = make_ref()
    task_timeout = Keyword.get(opts, :task_timeout, 30_000)
    max_retries = Keyword.get(opts, :max_retries, 0)

    task_info = %TaskInfo{
      ref: ref,
      client_pid: from_pid,
      func: task_func,
      task_timeout: task_timeout,
      max_retries: max_retries,
      attempts: 0
    }

    cond do
      length(state.idle_workers) > 0 ->
        [worker | rest] = state.idle_workers
        new_state = dispatch_to_worker(%{state | idle_workers: rest}, worker, task_info)
        {:reply, {:ok, ref}, new_state}

      :queue.len(state.queue) < state.max_queue ->
        new_state = %{state | queue: :queue.in(task_info, state.queue)}
        {:reply, {:ok, ref}, new_state}

      true ->
        {:reply, {:error, :queue_full}, state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      busy_workers: map_size(state.busy_workers),
      idle_workers: length(state.idle_workers),
      queue_length: :queue.len(state.queue),
      retry_count: state.retry_count
    }

    {:reply, status, state}
  end

  @impl true
  def handle_info({:task_finished, worker, ref, result}, state) do
    case Map.get(state.busy_workers, worker) do
      %TaskInfo{ref: ^ref} = task_info ->
        send(task_info.client_pid, {ref, :result, result})
        state = cancel_task_timer(state, worker)
        {:noreply, make_worker_available(state, worker)}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:task_timeout, worker_pid, ref}, state) do
    case Map.get(state.busy_workers, worker_pid) do
      %TaskInfo{ref: ^ref} = task_info ->
        # Kill the worker
        Process.exit(worker_pid, :kill)

        state = cancel_task_timer(state, worker_pid)

        # The :DOWN handler will handle replacement and retry/failure
        # But we need to mark this as a timeout, not a crash
        # We do this by storing the timeout info before the :DOWN arrives
        busy = Map.put(state.busy_workers, worker_pid, {:timed_out, task_info})
        {:noreply, %{state | busy_workers: busy}}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, mref, :process, pid, reason}, state) do
    new_monitors = Map.delete(state.monitors, mref)
    state = %{state | monitors: new_monitors}

    case Map.pop(state.busy_workers, pid) do
      {{:timed_out, task_info}, updated_busy} ->
        # Timeout-triggered kill
        state = %{state | busy_workers: updated_busy}
        state = cancel_task_timer(state, pid)
        handle_task_failure(state, task_info, :task_timeout)

      {%TaskInfo{} = task_info, updated_busy} ->
        # Genuine crash
        state = %{state | busy_workers: updated_busy}
        state = cancel_task_timer(state, pid)
        handle_task_failure(state, task_info, {:task_failed, reason})

      {nil, _} ->
        # Idle worker died somehow
        state = %{state | idle_workers: List.delete(state.idle_workers, pid)}
        {:ok, new_pid} = start_worker(state.sup)
        new_mref = Process.monitor(new_pid)

        final_state = %{state | monitors: Map.put(state.monitors, new_mref, new_pid)}
        {:noreply, make_worker_available(final_state, new_pid)}
    end
  end

  ## --- Private Helpers ---

  defp handle_task_failure(state, task_info, failure_type) do
    new_attempts = task_info.attempts

    if new_attempts <= task_info.max_retries do
      # Retry: re-enqueue at front of queue
      updated_task = task_info

      # Start replacement worker
      {:ok, new_pid} = start_worker(state.sup)
      new_mref = Process.monitor(new_pid)

      state = %{
        state
        | monitors: Map.put(state.monitors, new_mref, new_pid),
          queue: :queue.in_r(updated_task, state.queue),
          retry_count: state.retry_count + 1
      }

      {:noreply, make_worker_available(state, new_pid)}
    else
      # Exhausted retries — notify client
      error =
        case failure_type do
          :task_timeout -> {:task_timeout, new_attempts}
          {:task_failed, reason} -> {:task_failed, reason, new_attempts}
        end

      send(task_info.client_pid, {task_info.ref, :error, error})

      {:ok, new_pid} = start_worker(state.sup)
      new_mref = Process.monitor(new_pid)

      state = %{state | monitors: Map.put(state.monitors, new_mref, new_pid)}
      {:noreply, make_worker_available(state, new_pid)}
    end
  end

  defp dispatch_to_worker(state, worker, task_info) do
    updated_task = %{task_info | attempts: task_info.attempts + 1}
    send(worker, {:run, {updated_task.ref, updated_task.client_pid, updated_task.func}})

    # Set a timer for task timeout. The message carries the task ref: a
    # timer that fired just as its task finished leaves a stale message in
    # the mailbox, and worker pids are reused — without the ref match the
    # stale timeout would kill whatever task the worker runs NEXT.
    timer_ref =
      Process.send_after(
        self(),
        {:task_timeout, worker, updated_task.ref},
        updated_task.task_timeout
      )

    %{
      state
      | busy_workers: Map.put(state.busy_workers, worker, updated_task),
        worker_timers: Map.put(state.worker_timers, worker, timer_ref)
    }
  end

  defp make_worker_available(state, worker) do
    case :queue.out(state.queue) do
      {{:value, task_info}, remaining_queue} ->
        dispatch_to_worker(%{state | queue: remaining_queue}, worker, task_info)

      {:empty, _} ->
        %{
          state
          | idle_workers: [worker | state.idle_workers],
            busy_workers: Map.delete(state.busy_workers, worker)
        }
    end
  end

  defp cancel_task_timer(state, worker_pid) do
    case Map.pop(state.worker_timers, worker_pid) do
      {nil, _} ->
        state

      {timer_ref, new_worker_timers} ->
        Process.cancel_timer(timer_ref)
        %{state | worker_timers: new_worker_timers}
    end
  end

  defp start_worker(sup) do
    DynamicSupervisor.start_child(sup, {RetryPool.Worker, [self()]})
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
defmodule RetryPoolTest do
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

  # A task that fails N times, then succeeds
  defp flaky_task(counter_agent, fail_count, success_value) do
    fn ->
      count = Agent.get_and_update(counter_agent, fn n -> {n, n + 1} end)

      if count < fail_count do
        raise "attempt #{count + 1} failed"
      else
        success_value
      end
    end
  end

  setup do
    pool =
      start_supervised!(
        {RetryPool,
         pool_size: 2, max_queue: 5, name: :"pool_#{:erlang.unique_integer([:positive])}"}
      )

    %{pool: pool}
  end

  # -------------------------------------------------------
  # Basic submit / await (no retries)
  # -------------------------------------------------------

  test "submit and await a simple task", %{pool: pool} do
    {:ok, ref} = RetryPool.submit(pool, quick_task(42))
    assert {:ok, 42} = RetryPool.await(pool, ref, 1_000)
  end

  test "submit and await multiple tasks", %{pool: pool} do
    {:ok, r1} = RetryPool.submit(pool, quick_task(:a))
    {:ok, r2} = RetryPool.submit(pool, quick_task(:b))
    {:ok, r3} = RetryPool.submit(pool, quick_task(:c))

    assert {:ok, :a} = RetryPool.await(pool, r1, 1_000)
    assert {:ok, :b} = RetryPool.await(pool, r2, 1_000)
    assert {:ok, :c} = RetryPool.await(pool, r3, 1_000)
  end

  # -------------------------------------------------------
  # Crash without retries → immediate failure
  # -------------------------------------------------------

  test "crash with no retries returns task_failed immediately", %{pool: pool} do
    {:ok, ref} = RetryPool.submit(pool, fn -> raise "boom" end, max_retries: 0)
    assert {:error, {:task_failed, _reason, 1}} = RetryPool.await(pool, ref, 2_000)
  end

  # -------------------------------------------------------
  # Retry on crash
  # -------------------------------------------------------

  test "task that fails once then succeeds with max_retries: 1", %{pool: pool} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    {:ok, ref} =
      RetryPool.submit(
        pool,
        flaky_task(counter, 1, :recovered),
        max_retries: 1
      )

    assert {:ok, :recovered} = RetryPool.await(pool, ref, 3_000)

    # Should have tried twice total
    assert Agent.get(counter, & &1) == 2
    Agent.stop(counter)
  end

  test "task that exhausts all retries returns task_failed with attempt count", %{pool: pool} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    {:ok, ref} =
      RetryPool.submit(
        pool,
        flaky_task(counter, 100, :never),
        max_retries: 2
      )

    assert {:error, {:task_failed, _reason, 3}} = RetryPool.await(pool, ref, 5_000)

    # 1 initial + 2 retries = 3 total
    assert Agent.get(counter, & &1) == 3
    Agent.stop(counter)
  end

  test "retry_count in status increments with each retry", %{pool: pool} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    {:ok, ref} =
      RetryPool.submit(
        pool,
        flaky_task(counter, 2, :ok),
        max_retries: 3
      )

    assert {:ok, :ok} = RetryPool.await(pool, ref, 5_000)

    Process.sleep(100)

    status = RetryPool.status(pool)
    # Failed twice → 2 retries
    assert status.retry_count == 2
    Agent.stop(counter)
  end

  # -------------------------------------------------------
  # Per-task timeout
  # -------------------------------------------------------

  test "task that exceeds its timeout with no retries returns task_timeout", %{pool: pool} do
    {:ok, ref} =
      RetryPool.submit(
        pool,
        slow_task(2_000, :too_slow),
        task_timeout: 200,
        max_retries: 0
      )

    assert {:error, {:task_timeout, 1}} = RetryPool.await(pool, ref, 3_000)
  end

  test "task timeout triggers retry when retries remain", %{pool: pool} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    # First attempt times out, second attempt succeeds quickly
    {:ok, ref} =
      RetryPool.submit(
        pool,
        fn ->
          count = Agent.get_and_update(counter, fn n -> {n, n + 1} end)

          if count == 0 do
            # First attempt: sleep longer than timeout
            Process.sleep(5_000)
            :too_slow
          else
            :fast_enough
          end
        end,
        task_timeout: 200,
        max_retries: 1
      )

    assert {:ok, :fast_enough} = RetryPool.await(pool, ref, 5_000)
    Agent.stop(counter)
  end

  test "task timeout exhausting all retries returns task_timeout", %{pool: pool} do
    {:ok, ref} =
      RetryPool.submit(
        pool,
        slow_task(2_000, :never),
        task_timeout: 100,
        max_retries: 1
      )

    assert {:error, {:task_timeout, 2}} = RetryPool.await(pool, ref, 5_000)
  end

  # -------------------------------------------------------
  # Queue behavior
  # -------------------------------------------------------

  test "tasks are queued when all workers are busy", %{pool: pool} do
    gate = self()

    {:ok, _} = RetryPool.submit(pool, blocking_task(gate))
    {:ok, _} = RetryPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    {:ok, r3} = RetryPool.submit(pool, quick_task(:queued))

    status = RetryPool.status(pool)
    assert status.queue_length >= 1

    release(w1)
    release(w2)

    assert {:ok, :queued} = RetryPool.await(pool, r3, 2_000)
  end

  test "queue rejects when full", %{pool: pool} do
    # TODO
  end

  test "queued tasks execute in FIFO order", %{pool: pool} do
    collector = self()
    gate = self()

    {:ok, _} = RetryPool.submit(pool, blocking_task(gate))
    {:ok, _} = RetryPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    for i <- 1..3 do
      RetryPool.submit(pool, fn ->
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
  # Pool resilience
  # -------------------------------------------------------

  test "pool remains functional after crashes and retries", %{pool: pool} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    {:ok, ref} =
      RetryPool.submit(pool, flaky_task(counter, 100, :never), max_retries: 2)

    RetryPool.await(pool, ref, 5_000)
    Process.sleep(200)

    {:ok, ref2} = RetryPool.submit(pool, quick_task(:after_retries))
    assert {:ok, :after_retries} = RetryPool.await(pool, ref2, 1_000)
    Agent.stop(counter)
  end

  test "worker count is restored after crashes", %{pool: pool} do
    {:ok, ref} = RetryPool.submit(pool, fn -> raise "die" end, max_retries: 0)
    RetryPool.await(pool, ref, 2_000)

    Process.sleep(200)

    status = RetryPool.status(pool)
    assert status.idle_workers + status.busy_workers == 2
  end

  # -------------------------------------------------------
  # Status introspection
  # -------------------------------------------------------

  test "status reflects pool state accurately", %{pool: pool} do
    status = RetryPool.status(pool)
    assert status.idle_workers == 2
    assert status.busy_workers == 0
    assert status.queue_length == 0
    assert status.retry_count == 0
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "pool_size of 1 works correctly", _context do
    pool =
      start_supervised!(
        {RetryPool, pool_size: 1, max_queue: 2, name: :single_retry_pool},
        id: :single
      )

    {:ok, r1} = RetryPool.submit(pool, quick_task(:only))
    assert {:ok, :only} = RetryPool.await(pool, r1, 1_000)
  end

  test "await with an unknown ref times out", %{pool: pool} do
    bogus_ref = make_ref()
    assert {:error, _} = RetryPool.await(pool, bogus_ref, 200)
  end

  test "max_retries of 0 is the default — no retries", %{pool: pool} do
    {:ok, ref} = RetryPool.submit(pool, fn -> raise "once" end)
    assert {:error, {:task_failed, _reason, 1}} = RetryPool.await(pool, ref, 2_000)
  end

  test "await timeout fires even while task is being retried", %{pool: pool} do
    # Task that always fails, with many retries and a long timeout
    {:ok, ref} =
      RetryPool.submit(
        pool,
        fn ->
          Process.sleep(500)
          raise "slow fail"
        end,
        max_retries: 10,
        task_timeout: 30_000
      )

    # Await with a short timeout — should not wait for all retries
    assert {:error, :timeout} = RetryPool.await(pool, ref, 200)
  end

  test "a timed-out retry runs before an already-queued task", _context do
    pool =
      start_supervised!(
        {RetryPool, pool_size: 1, max_queue: 5, name: :added_to_front_pool},
        id: :added_to_front
      )

    {:ok, counter} = Agent.start_link(fn -> 0 end)
    collector = self()

    task_a = fn ->
      n = Agent.get_and_update(counter, fn n -> {n, n + 1} end)

      if n == 0 do
        Process.sleep(2_000)
        :a_slow
      else
        send(collector, {:executed, :a})
        :a_ok
      end
    end

    {:ok, _ra} = RetryPool.submit(pool, task_a, task_timeout: 200, max_retries: 1)

    {:ok, _rb} =
      RetryPool.submit(pool, fn ->
        send(collector, {:executed, :b})
        :b_ok
      end)

    assert_receive {:executed, first}, 3_000
    assert first == :a
    assert_receive {:executed, second}, 3_000
    assert second == :b

    Agent.stop(counter)
  end

  test "a crashed retry jumps ahead of an already-queued task", _context do
    pool =
      start_supervised!(
        {RetryPool, pool_size: 1, max_queue: 5, name: :added_front_pool},
        id: :added_front
      )

    {:ok, counter} = Agent.start_link(fn -> 0 end)
    collector = self()

    task_a = fn ->
      n = Agent.get_and_update(counter, fn n -> {n, n + 1} end)

      if n == 0 do
        send(collector, {:ready_a, self()})

        receive do
          :proceed -> raise "a fails first time"
        end
      else
        send(collector, {:executed, :a})
        :a_ok
      end
    end

    {:ok, _ra} = RetryPool.submit(pool, task_a, max_retries: 1)
    assert_receive {:ready_a, worker_a}, 1_000

    {:ok, _rb} =
      RetryPool.submit(pool, fn ->
        send(collector, {:executed, :b})
        :b_ok
      end)

    release(worker_a)

    assert_receive {:executed, first}, 2_000
    assert first == :a
    assert_receive {:executed, second}, 2_000
    assert second == :b

    Agent.stop(counter)
  end

  test "pool_size defaults to 3 idle workers", _context do
    pool =
      start_supervised!(
        {RetryPool, name: :added_default_pool},
        id: :added_default
      )

    status = RetryPool.status(pool)
    assert status.idle_workers == 3
    assert status.busy_workers == 0
  end

  test "max_queue defaults to 10 pending tasks", _context do
    pool =
      start_supervised!(
        {RetryPool, name: :added_maxq_pool},
        id: :added_maxq
      )

    gate = self()

    for _ <- 1..3 do
      {:ok, _} = RetryPool.submit(pool, blocking_task(gate))
    end

    workers =
      for _ <- 1..3 do
        assert_receive {:ready, w}, 1_000
        w
      end

    for _ <- 1..10 do
      {:ok, _} = RetryPool.submit(pool, quick_task(:filler))
    end

    assert {:error, :queue_full} = RetryPool.submit(pool, quick_task(:overflow))

    Enum.each(workers, &release/1)
  end

  test "pool_size: 0 starts exactly zero workers" do
    pool =
      start_supervised!(
        {RetryPool,
         pool_size: 0, max_queue: 5, name: :"pool_zero_#{:erlang.unique_integer([:positive])}"},
        id: :zero_pool
      )

    status = RetryPool.status(pool)
    assert status.idle_workers == 0
    assert status.busy_workers == 0

    # With no workers the task can only queue — it must never run.
    {:ok, ref} = RetryPool.submit(pool, quick_task(:never))
    assert {:error, :timeout} = RetryPool.await(pool, ref, 150)
    assert RetryPool.status(pool).queue_length == 1
  end

  test "await delivers to the submitting process only, as documented", %{pool: pool} do
    {:ok, ref} = RetryPool.submit(pool, quick_task(:mine))

    # Another process awaiting the same ref gets nothing: results are
    # messages in the SUBMITTER's mailbox.
    other =
      Task.async(fn ->
        RetryPool.await(pool, ref, 150)
      end)

    assert {:error, :timeout} = Task.await(other, 1_000)

    # The submitter still receives the result afterwards.
    assert {:ok, :mine} = RetryPool.await(pool, ref, 1_000)
  end
end
```
