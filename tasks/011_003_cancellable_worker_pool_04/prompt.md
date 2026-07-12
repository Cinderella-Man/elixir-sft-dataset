Implement the `handle_info/2` GenServer callback for the `CancellablePool` manager.
It has two clauses, one per message the manager can receive from its workers and
monitors.

**Clause 1 — `{:task_finished, worker, ref, result}`** is sent by a worker when it
finishes running a task. Look up `worker` in `busy_workers`. If the entry matches the
expected `ref` (i.e. it is `{^ref, client_pid}`), send the awaiting client the message
`{ref, :result, result}`, then hand the worker its next unit of work by returning
`dispatch_next(state, worker)` as the new state (this pulls the next queued task if one
is pending, otherwise marks the worker idle). If the entry does not match (a stale or
unexpected message), leave the state unchanged.

**Clause 2 — `{:DOWN, mref, :process, pid, reason}`** fires when a monitored worker
dies. First drop `mref` from `monitors`. Then figure out what the dead `pid` was doing:

- If it was a busy worker, pop it out of `busy_workers`. Check whether its `ref` is in
  `cancelled_refs`. If it was cancelled, the client was already told in the cancel
  handler, so just remove the worker from `busy_workers` and delete the ref from
  `cancelled_refs`. If it was **not** cancelled, this is a genuine crash: notify the
  awaiting client with `{ref, :error, {:task_crashed, reason}}` and remove the worker
  from `busy_workers`.
- If it was not busy, it was an idle worker — remove it from `idle_workers`.

Regardless of which case applied, start a replacement worker with `start_worker/1`,
monitor it, record the new monitor in `monitors`, and finally return
`dispatch_next(final_state, new_pid)` so the fresh worker immediately picks up a queued
task if one is waiting. No reply is sent for either clause.

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

  def handle_info({:task_finished, worker, ref, result}, state) do
    # TODO
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