defmodule CancellablePool do
  @moduledoc """
  A pool of worker `GenServer`s with a bounded FIFO task queue and task cancellation.

  ## Design

    * A manager process (this module) owns the pool state: the worker set, the pending
      task queue, completed results and the waiters blocked in `await/3`.
    * Workers are started under a `DynamicSupervisor` (owned and linked to the manager)
      as `:temporary` children, so the manager decides when a replacement is started.
    * Each task is identified by a unique `t:reference/0` returned by `submit/2`.

  ## Semantics

    * `submit/2` dispatches immediately when a worker is idle and the queue is empty,
      otherwise it enqueues the task while the queue has room, and returns
      `{:error, :queue_full}` when the queue is full.
    * Tasks always run in submission order; a worker that finishes a task immediately
      pulls the next pending task from the queue.
    * `cancel/2` removes a still-pending task from the queue, or kills the worker that is
      currently running the task and starts a replacement worker (which then picks up the
      next queued task, if any). Awaiters of a cancelled task get `{:error, :cancelled}`.
    * If a worker crashes while running a task, the awaiter of that task receives
      `{:error, {:task_crashed, reason}}`, a replacement worker is started and the queued
      tasks are preserved.

  ## Example

      {:ok, pool} = CancellablePool.start_link(pool_size: 2, max_queue: 5)
      {:ok, ref} = CancellablePool.submit(pool, fn -> 1 + 1 end)
      {:ok, 2} = CancellablePool.await(pool, ref)
  """

  use GenServer

  alias CancellablePool.Worker

  @default_pool_size 3
  @default_max_queue 10
  @default_timeout 5_000

  @typedoc "A reference to the pool manager process."
  @type pool :: GenServer.server()

  @typedoc "The outcome of a submitted task, as delivered to `await/3`."
  @type task_result ::
          {:ok, term()}
          | {:error, :cancelled}
          | {:error, :timeout}
          | {:error, {:task_crashed, term()}}

  @typedoc "A snapshot of the pool state."
  @type status :: %{
          busy_workers: non_neg_integer(),
          idle_workers: non_neg_integer(),
          queue_length: non_neg_integer(),
          cancelled_count: non_neg_integer()
        }

  # ── Public API ──────────────────────────────────────────────────────────────────────

  @doc """
  Starts the pool manager and its worker processes.

  ## Options

    * `:pool_size` - number of worker processes (default `#{@default_pool_size}`)
    * `:max_queue` - maximum number of pending tasks in the queue (default `#{@default_max_queue}`)
    * `:name` - optional name under which the manager is registered

  Returns `{:ok, pid}` on success.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    case name do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @doc """
  Submits a zero-arity function to the pool.

  Dispatches the task immediately when a worker is idle and nothing is queued ahead of it,
  otherwise enqueues it. Returns `{:ok, ref}` where `ref` identifies the task for `await/3`
  and `cancel/2`, or `{:error, :queue_full}` when all workers are busy and the queue is full.
  """
  @spec submit(pool(), (-> term())) :: {:ok, reference()} | {:error, :queue_full}
  def submit(pool, task_func) when is_function(task_func, 0) do
    GenServer.call(pool, {:submit, task_func})
  end

  @doc """
  Cancels the task identified by `ref`.

  A pending task is removed from the queue; a running task has its worker killed and
  replaced. In both cases awaiters receive `{:error, :cancelled}` and `:ok` is returned.
  Returns `{:error, :not_found}` when the task already completed, was already cancelled or
  never existed.
  """
  @spec cancel(pool(), reference()) :: :ok | {:error, :not_found}
  def cancel(pool, ref) when is_reference(ref) do
    GenServer.call(pool, {:cancel, ref})
  end

  @doc """
  Waits for the result of the task identified by `ref`.

  Blocks the caller until the result is available or `timeout` milliseconds elapse.
  Returns `{:ok, result}`, `{:error, :cancelled}`, `{:error, {:task_crashed, reason}}` or
  `{:error, :timeout}`.
  """
  @spec await(pool(), reference(), timeout()) :: task_result()
  def await(pool, ref, timeout \\ @default_timeout) when is_reference(ref) do
    await_ref = make_ref()
    GenServer.cast(pool, {:await, ref, self(), await_ref})

    receive do
      {:pool_result, ^await_ref, result} -> result
    after
      timeout ->
        GenServer.cast(pool, {:drop_await, ref, await_ref})

        # The result may have been delivered concurrently with the timeout firing.
        receive do
          {:pool_result, ^await_ref, result} -> result
        after
          0 -> {:error, :timeout}
        end
    end
  end

  @doc """
  Returns a snapshot of the pool: busy/idle worker counts, queue length and the cumulative
  number of tasks cancelled since the pool started.
  """
  @spec status(pool()) :: status()
  def status(pool) do
    GenServer.call(pool, :status)
  end

  # ── GenServer callbacks ─────────────────────────────────────────────────────────────

  @impl GenServer
  @doc false
  def init(opts) do
    pool_size = Keyword.get(opts, :pool_size, @default_pool_size)
    max_queue = Keyword.get(opts, :max_queue, @default_max_queue)

    {:ok, sup} = DynamicSupervisor.start_link(strategy: :one_for_one)

    state = %{
      sup: sup,
      pool_size: pool_size,
      max_queue: max_queue,
      workers: %{},
      queue: :queue.new(),
      queue_len: 0,
      results: %{},
      waiters: %{},
      cancelled_count: 0
    }

    state = Enum.reduce(1..pool_size//1, state, fn _i, acc -> start_worker(acc) end)
    {:ok, state}
  end

  @impl GenServer
  @doc false
  def handle_call({:submit, fun}, _from, state) do
    ref = make_ref()
    idle = idle_worker(state)

    cond do
      state.queue_len == 0 and idle != nil ->
        {:reply, {:ok, ref}, dispatch(state, idle, ref, fun)}

      state.queue_len < state.max_queue ->
        state = %{
          state
          | queue: :queue.in({ref, fun}, state.queue),
            queue_len: state.queue_len + 1
        }

        {:reply, {:ok, ref}, pump(state)}

      true ->
        {:reply, {:error, :queue_full}, state}
    end
  end

  def handle_call({:cancel, ref}, _from, state) do
    cond do
      pid = running_worker(state, ref) ->
        {:reply, :ok, cancel_running(state, pid, ref)}

      queued?(state, ref) ->
        {:reply, :ok, cancel_queued(state, ref)}

      true ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:status, _from, state) do
    busy = Enum.count(state.workers, fn {_pid, w} -> w.task != nil end)

    status = %{
      busy_workers: busy,
      idle_workers: map_size(state.workers) - busy,
      queue_length: state.queue_len,
      cancelled_count: state.cancelled_count
    }

    {:reply, status, state}
  end

  @impl GenServer
  @doc false
  def handle_cast({:await, ref, pid, await_ref}, state) do
    case Map.fetch(state.results, ref) do
      {:ok, result} ->
        send(pid, {:pool_result, await_ref, result})
        {:noreply, state}

      :error ->
        waiters = Map.update(state.waiters, ref, [{pid, await_ref}], &[{pid, await_ref} | &1])
        {:noreply, %{state | waiters: waiters}}
    end
  end

  def handle_cast({:drop_await, ref, await_ref}, state) do
    case Map.fetch(state.waiters, ref) do
      {:ok, list} ->
        case Enum.reject(list, fn {_pid, aref} -> aref == await_ref end) do
          [] -> {:noreply, %{state | waiters: Map.delete(state.waiters, ref)}}
          rest -> {:noreply, %{state | waiters: Map.put(state.waiters, ref, rest)}}
        end

      :error ->
        {:noreply, state}
    end
  end

  @impl GenServer
  @doc false
  def handle_info({:task_done, pid, ref, value}, state) do
    case Map.fetch(state.workers, pid) do
      {:ok, %{task: ^ref}} ->
        state =
          state
          |> put_in([:workers, pid, :task], nil)
          |> deliver(ref, {:ok, value})
          |> pump()

        {:noreply, state}

      _other ->
        # Stale message from a worker that was cancelled or is no longer tracked.
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, _mon, :process, pid, reason}, state) do
    case Map.fetch(state.workers, pid) do
      {:ok, %{task: task}} ->
        state = %{state | workers: Map.delete(state.workers, pid)}

        state =
          if task do
            deliver(state, task, {:error, {:task_crashed, reason}})
          else
            state
          end

        {:noreply, state |> start_worker() |> pump()}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Internal helpers ────────────────────────────────────────────────────────────────

  defp start_worker(state) do
    spec = %{
      id: Worker,
      start: {Worker, :start_link, [self()]},
      restart: :temporary,
      type: :worker
    }

    {:ok, pid} = DynamicSupervisor.start_child(state.sup, spec)
    mon = Process.monitor(pid)
    %{state | workers: Map.put(state.workers, pid, %{mon: mon, task: nil})}
  end

  defp idle_worker(state) do
    Enum.find_value(state.workers, fn
      {pid, %{task: nil}} -> pid
      {_pid, _worker} -> nil
    end)
  end

  defp running_worker(state, ref) do
    Enum.find_value(state.workers, fn
      {pid, %{task: ^ref}} -> pid
      {_pid, _worker} -> nil
    end)
  end

  defp queued?(state, ref) do
    Enum.any?(:queue.to_list(state.queue), fn {r, _fun} -> r == ref end)
  end

  defp dispatch(state, pid, ref, fun) do
    :ok = Worker.run(pid, ref, fun)
    put_in(state, [:workers, pid, :task], ref)
  end

  # Keeps handing queued tasks to idle workers, preserving FIFO order.
  defp pump(state) do
    with pid when is_pid(pid) <- idle_worker(state),
         {{:value, {ref, fun}}, queue} <- :queue.out(state.queue) do
      state = %{state | queue: queue, queue_len: state.queue_len - 1}

      state
      |> dispatch(pid, ref, fun)
      |> pump()
    else
      _ -> state
    end
  end

  defp cancel_queued(state, ref) do
    remaining =
      state.queue
      |> :queue.to_list()
      |> Enum.reject(fn {r, _fun} -> r == ref end)

    state = %{
      state
      | queue: :queue.from_list(remaining),
        queue_len: length(remaining),
        cancelled_count: state.cancelled_count + 1
    }

    state
    |> deliver(ref, {:error, :cancelled})
    |> pump()
  end

  defp cancel_running(state, pid, ref) do
    %{mon: mon} = Map.fetch!(state.workers, pid)
    Process.demonitor(mon, [:flush])
    Process.exit(pid, :kill)

    state = %{
      state
      | workers: Map.delete(state.workers, pid),
        cancelled_count: state.cancelled_count + 1
    }

    state
    |> deliver(ref, {:error, :cancelled})
    |> start_worker()
    |> pump()
  end

  defp deliver(state, ref, result) do
    for {pid, await_ref} <- Map.get(state.waiters, ref, []) do
      send(pid, {:pool_result, await_ref, result})
    end

    %{
      state
      | results: Map.put(state.results, ref, result),
        waiters: Map.delete(state.waiters, ref)
    }
  end

  defmodule Worker do
    @moduledoc false
    # A pool worker: runs one task at a time and reports the value back to the manager.
    # A task that raises simply crashes the worker; the manager turns the exit reason into
    # `{:error, {:task_crashed, reason}}` for the awaiting caller.

    use GenServer

    @doc false
    @spec start_link(pid()) :: GenServer.on_start()
    def start_link(manager) when is_pid(manager) do
      GenServer.start_link(__MODULE__, manager)
    end

    @doc false
    @spec run(pid(), reference(), (-> term())) :: :ok
    def run(worker, ref, fun) when is_pid(worker) and is_reference(ref) do
      GenServer.cast(worker, {:run, ref, fun})
    end

    @impl GenServer
    @doc false
    def init(manager) do
      {:ok, %{manager: manager}}
    end

    @impl GenServer
    @doc false
    def handle_cast({:run, ref, fun}, %{manager: manager} = state) do
      value = fun.()
      send(manager, {:task_done, self(), ref, value})
      {:noreply, state}
    end
  end
end