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
      {^ref, :error, reason}  -> {:error, reason}
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
      busy_workers: %{}, # %{worker_pid => {ref, client_pid}}
      monitors: %{}      # %{monitor_ref => worker_pid}
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
    new_state = Enum.reduce(1..pool_size, state, fn _, acc ->
      {:ok, pid} = start_worker(acc.sup)
      mref = Process.monitor(pid)
      %{acc | idle_workers: [pid | acc.idle_workers],
              monitors: Map.put(acc.monitors, mref, pid)}
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

        new_state = %{state |
          idle_workers: rest,
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
    state = case Map.pop(state.busy_workers, pid) do
      {{ref, client_pid}, updated_busy} ->
        send(client_pid, {ref, :error, {:task_crashed, reason}})
        %{state | busy_workers: updated_busy}
      {nil, _} ->
        %{state | idle_workers: List.delete(state.idle_workers, pid)}
    end

    # Replace the crashed worker
    {:ok, new_worker_pid} = start_worker(state.sup)
    new_mref = Process.monitor(new_worker_pid)

    final_state = %{state |
      monitors: Map.put(new_monitors, new_mref, new_worker_pid)
    }

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
        %{state |
          queue: remaining_queue,
          busy_workers: Map.put(state.busy_workers, worker, {ref, client_pid})
        }
      {:empty, _} ->
        %{state |
          idle_workers: [worker | state.idle_workers],
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
