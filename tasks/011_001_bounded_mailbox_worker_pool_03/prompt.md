Implement the `handle_info/2` GenServer callback for the `WorkerPool` manager. Two
distinct messages arrive at the manager and each needs its own clause.

**1. Task completion — `{:task_finished, worker, ref, result}`**

A worker sends this once it finishes running a task. Look up `worker` in
`busy_workers`. If it is present and its stored `{ref, client_pid}` matches the
incoming `ref`, forward the result to the awaiting caller by sending it
`{ref, :result, result}`, then free the worker and let it pick up the next queued
task via `dispatch_next/2`. If the worker is unknown or the ref doesn't match
(a stale or duplicate message), ignore it and leave the state unchanged. Always
reply with `{:noreply, state}`.

**2. Worker crash — `{:DOWN, mref, :process, pid, reason}`**

A monitored worker went down. First drop `mref` from `monitors`. Then determine
what the crashed worker was doing:

- If it was busy (found in `busy_workers`), notify that task's client that its task
  crashed by sending `{ref, :error, {:task_crashed, reason}}`, and remove the worker
  from `busy_workers`.
- If it was idle, just remove it from `idle_workers`.

Regardless, start a replacement worker with `start_worker/1`, monitor it, and record
the new monitor ref → pid mapping in `monitors`. Finally, hand the fresh worker a task
from the queue if one is pending by running it through `dispatch_next/2`, and reply
with `{:noreply, ...}` carrying the updated state. This keeps queued tasks from being
lost and keeps the pool fully functional after a crash.

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
    # TODO
  end

  @impl true
  def handle_info({:DOWN, mref, :process, pid, reason}, state) do
    # TODO
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
```