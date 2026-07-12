Implement the `handle_call/3` GenServer callback for `CancellablePool`. It has three
clauses — one per kind of synchronous request the manager receives. Together they form
the whole function; implement each clause's body.

1. **`{:submit, task_func}`** — the calling process's pid is the first element of the
   `from` tuple. Generate a fresh unique reference with `make_ref/0` and build a task
   tuple `{ref, from_pid, task_func}`. Then:
   - If there is at least one idle worker, take the head of `idle_workers`, send it
     `{:run, task}`, move it into `busy_workers` as `worker => {ref, from_pid}`, drop it
     from `idle_workers`, and reply `{:ok, ref}`.
   - Otherwise, if the queue holds fewer than `max_queue` tasks, enqueue the task,
     record the ref as pending in `pending_refs` (`ref => from_pid`), and reply
     `{:ok, ref}`.
   - Otherwise the queue is full: reply `{:error, :queue_full}` and leave state
     unchanged.

2. **`{:cancel, ref}`** — attempt to cancel the task identified by `ref`:
   - First look the ref up in `pending_refs` (still queued). If found, remove it from the
     queue with `queue_remove/2`, send the client `{ref, :error, :cancelled}`, drop the
     ref from `pending_refs`, increment `cancelled_count`, and reply `:ok`.
   - Otherwise check whether the ref is running on a busy worker via
     `find_busy_worker/2`. If so, add the ref to `cancelled_refs` (so the `:DOWN`
     handler knows this was a cancellation rather than a crash), kill the worker with
     `Process.exit(worker_pid, :kill)`, send the client `{ref, :error, :cancelled}`,
     increment `cancelled_count`, and reply `:ok`.
   - If the ref is neither pending nor running, reply `{:error, :not_found}`.

3. **`:status`** — reply with a map containing `:busy_workers` (the number of busy
   workers), `:idle_workers` (the number of idle workers), `:queue_length` (the current
   queue length), and `:cancelled_count` (the cumulative cancelled count), leaving state
   unchanged.

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

  def handle_call({:submit, task_func}, {from_pid, _}, state) do
    # TODO
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