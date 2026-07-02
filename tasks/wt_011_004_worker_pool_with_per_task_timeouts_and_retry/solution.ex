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
      # %{timer_ref => worker_pid} for task timeouts
      timers: %{},
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
  def handle_info({:task_timeout, worker_pid}, state) do
    case Map.get(state.busy_workers, worker_pid) do
      %TaskInfo{} = task_info ->
        # Kill the worker
        Process.exit(worker_pid, :kill)

        state = cancel_task_timer(state, worker_pid)

        # The :DOWN handler will handle replacement and retry/failure
        # But we need to mark this as a timeout, not a crash
        # We do this by storing the timeout info before the :DOWN arrives
        {:noreply, %{state | busy_workers: Map.put(state.busy_workers, worker_pid, {:timed_out, task_info})}}

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

      state = %{state |
        monitors: Map.put(state.monitors, new_mref, new_pid),
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

    # Set a timer for task timeout
    timer_ref = Process.send_after(self(), {:task_timeout, worker}, updated_task.task_timeout)

    %{
      state
      | busy_workers: Map.put(state.busy_workers, worker, updated_task),
        timers: Map.put(state.timers, timer_ref, worker),
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

        %{
          state
          | worker_timers: new_worker_timers,
            timers: Map.delete(state.timers, timer_ref)
        }
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
