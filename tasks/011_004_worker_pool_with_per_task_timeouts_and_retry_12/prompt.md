# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `cancel_task_timer`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

Hey — I need you to write me an Elixir module called `RetryPool` that manages a pool of worker GenServers with a bounded task queue, per-task execution timeouts, and automatic retry on failure. I'd like the complete implementation in a single file, using only the OTP standard library (GenServer, DynamicSupervisor, etc.) — no external dependencies, please.

Here's the public API I'm after. First, `RetryPool.start_link(opts)` to start the pool supervisor/manager. It should accept `:pool_size` (number of worker processes, default 3), `:max_queue` (maximum pending tasks in the queue, default 10), and a `:name` option for process registration.

Next, `RetryPool.submit(pool, task_func, opts \\ [])`, where `task_func` is a zero-arity function to execute. Its options include `:task_timeout` (max milliseconds a single execution attempt may run, default 30_000) and `:max_retries` (number of retry attempts after the initial try, default 0 meaning no retries). The dispatch logic I want: if a worker is idle, dispatch immediately; if all workers are busy but the queue isn't full, enqueue it; if the queue is full, return `{:error, :queue_full}`. On success return `{:ok, ref}`.

Then `RetryPool.await(pool, ref, timeout \\ 5_000)`, which blocks the caller until the final result for `ref` is available or the timeout expires. It should return `{:ok, result}` if the task completed successfully (on any attempt), `{:error, :timeout}` if the await timeout fires, `{:error, {:task_failed, reason, attempts}}` if the task exhausted all retries where `attempts` is the total number of attempts made, or `{:error, {:task_timeout, attempts}}` if the task timed out on its final attempt (again `attempts` is the total number of attempts made). One important detail: `await` must be called from the same process that called `submit` for that `ref` — results are delivered as plain messages to the submitter's mailbox, so any other process awaiting the ref just times out.

Finally, `RetryPool.status(pool)`, which returns a map whose values are all non-negative integers, with keys `:busy_workers` (count of workers currently executing a task), `:idle_workers` (count of workers waiting for work), `:queue_length` (number of pending tasks in the queue), and `:retry_count` (cumulative number of retry attempts made since pool start).

On task timeout enforcement: when a worker has been executing a task for longer than `:task_timeout`, the pool must kill the worker, start a replacement, and either retry the task (if retries remain) or report failure to the awaiter. A timed-out task that still has retries remaining should be re-enqueued at the front of the queue (to preserve fairness — it already waited once).

For task crash handling: if a worker crashes (raises an exception) while executing a task, the same retry logic applies — retry if attempts remain, otherwise report `{:error, {:task_failed, reason, attempts}}`.

A couple of queue semantics to keep straight: the queue is FIFO for new submissions, retried tasks go to the front of the queue, and when a worker finishes a task it should automatically pull the next task from the queue if one is pending.

Workers must be supervised, and the pool itself should remain fully functional after any worker crash or timeout.

## The module with `cancel_task_timer` missing

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
    # TODO
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

Output only `cancel_task_timer` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
