# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

# Design Brief: `CancellablePool`

## Problem

We need an Elixir module called `CancellablePool` that manages a pool of worker GenServers backed by a bounded task queue, with support for cancelling tasks that are either waiting or already running. Deliver the complete implementation in a single file.

## Constraints

- Use only the OTP standard library (GenServer, DynamicSupervisor, etc.). No external dependencies.
- Tasks must execute in submission order — the queue is FIFO.
- When a worker finishes a task, it should automatically pull the next task from the queue if one is pending.
- Workers must be supervised. If a worker crashes mid-task (not via cancellation), the pool should start a replacement worker, the caller awaiting that task's ref should get `{:error, {:task_crashed, reason}}`, and any remaining queued tasks should not be lost. A task that raises an exception while running counts as such a crash. The pool itself should remain fully functional after a worker crash.
- When a running task is cancelled, the replacement worker should immediately pick up the next queued task if one exists.

## Required Interface

1. `CancellablePool.start_link(opts)` — starts the pool supervisor/manager. It should accept `:pool_size` (number of worker processes, default 3), `:max_queue` (maximum pending tasks in the queue, default 10), and `:name` option for process registration.

2. `CancellablePool.submit(pool, task_func)` — where `task_func` is a zero-arity function to execute. If a worker is idle, dispatch immediately. If all workers are busy but the queue isn't full, enqueue it. If the queue is full, return `{:error, :queue_full}`. On success return `{:ok, ref}` where `ref` is a unique reference the caller can use to retrieve the result later or cancel the task.

3. `CancellablePool.cancel(pool, ref)` — attempts to cancel a task identified by `ref`. If the task is still queued (pending), remove it from the queue and return `:ok` — the awaiter should receive `{:error, :cancelled}`. If the task is currently running on a worker, kill the worker, start a replacement, and return `:ok` — the awaiter should receive `{:error, :cancelled}`. If the ref is unknown (already completed, already cancelled, or never existed), return `{:error, :not_found}`.

4. `CancellablePool.await(pool, ref, timeout \\ 5_000)` — blocks the caller until the result for `ref` is available or the timeout expires. Return `{:ok, result}` if the task completed successfully, `{:error, :timeout}` if the timeout fires, `{:error, :cancelled}` if the task was cancelled, or `{:error, {:task_crashed, reason}}` if the worker crashed while executing that task. An unknown ref should simply block until the timeout and then return `{:error, :timeout}`.

5. `CancellablePool.status(pool)` — returns a map with keys `:busy_workers`, `:idle_workers`, `:queue_length`, and `:cancelled_count` (cumulative count of tasks cancelled since pool start).

## Acceptance Criteria

- `submit/2` dispatches to an idle worker immediately, enqueues when all workers are busy and the queue has room, and returns `{:error, :queue_full}` when the queue is full; successful submissions return `{:ok, ref}` with a unique `ref`.
- Queued tasks run in FIFO submission order, and a worker that finishes automatically pulls the next pending task from the queue.
- Cancelling a pending (queued) task removes it from the queue, returns `:ok`, and causes its awaiter to receive `{:error, :cancelled}`.
- Cancelling a running task kills the worker, starts a replacement, returns `:ok`, causes its awaiter to receive `{:error, :cancelled}`, and the replacement worker immediately picks up the next queued task if one exists.
- Cancelling an unknown ref (already completed, already cancelled, or never existed) returns `{:error, :not_found}`.
- `await/3` returns `{:ok, result}` on success, `{:error, :timeout}` on timeout, `{:error, :cancelled}` when cancelled, and `{:error, {:task_crashed, reason}}` when the worker crashed executing that task; an unknown ref blocks until the timeout and then returns `{:error, :timeout}`.
- On a mid-task worker crash (including a task that raises an exception), the pool starts a replacement worker, the awaiter of that task's ref gets `{:error, {:task_crashed, reason}}`, remaining queued tasks are preserved, and the pool remains fully functional.
- `status/1` returns a map with `:busy_workers`, `:idle_workers`, `:queue_length`, and `:cancelled_count` (cumulative count of tasks cancelled since pool start).
- The implementation is a single file using only the OTP standard library, with `:pool_size` defaulting to 3, `:max_queue` defaulting to 10, and a supported `:name` registration option.

## The buggy module

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

      false ->
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

## Failing test report

```
2 of 18 test(s) failed:

  * test cancelling a pending task frees a queue slot
      :exit: {{:cond_clause, [{CancellablePool, :handle_call, 3, [file: ~c".gen_staging/bugfix_011_003_cancellable_worker_pool_02_mutant.ex", line: 119]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]}, {GenServer, :call, [#PID<0.233.0>, {:submit, #Function<1.115278386/0 in CancellablePoolTest.quick_task/1>}, 5000]}}

  * test queue rejects when full
      :exit: {{:cond_clause, [{CancellablePool, :handle_call, 3, [file: ~c".gen_staging/bugfix_011_003_cancellable_worker_pool_02_mutant.ex", line: 119]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]}, {GenServer, :call, [#PID<0.281.0>, {:submit, #Function<1.115278386/0 in CancellablePoolTest.quick_task/1>}, 5000]}}
```
