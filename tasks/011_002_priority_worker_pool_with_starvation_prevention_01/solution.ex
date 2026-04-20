defmodule PriorityWorkerPool do
  @moduledoc """
  A priority-based bounded-queue worker pool with starvation prevention.
  """

  use GenServer

  @priorities [:high, :normal, :low]

  ## --- Public API ---

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec submit(GenServer.server(), (-> any()), :high | :normal | :low) ::
          {:ok, reference()} | {:error, :queue_full}
  def submit(pool, task_func, priority \\ :normal)
      when is_function(task_func, 0) and priority in @priorities do
    GenServer.call(pool, {:submit, task_func, priority})
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
      :promote_after_ms,
      # %{priority => :queue.queue({ref, client_pid, func, enqueued_at})}
      queues: %{high: :queue.new(), normal: :queue.new(), low: :queue.new()},
      idle_workers: [],
      busy_workers: %{},
      monitors: %{}
    ]
  end

  @impl true
  def init(opts) do
    pool_size = Keyword.get(opts, :pool_size, 3)
    max_queue = Keyword.get(opts, :max_queue, 10)
    promote_after_ms = Keyword.get(opts, :promote_after_ms, 5_000)

    {:ok, sup} = DynamicSupervisor.start_link(strategy: :one_for_one)

    state = %State{
      sup: sup,
      pool_size: pool_size,
      max_queue: max_queue,
      promote_after_ms: promote_after_ms
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

    schedule_promotion(promote_after_ms)

    {:ok, new_state}
  end

  @impl true
  def handle_call({:submit, task_func, priority}, {from_pid, _}, state) do
    ref = make_ref()
    now = System.monotonic_time(:millisecond)
    task = {ref, from_pid, task_func, now}

    cond do
      length(state.idle_workers) > 0 ->
        [worker | rest] = state.idle_workers
        send(worker, {:run, {ref, from_pid, task_func}})

        new_state = %{
          state
          | idle_workers: rest,
            busy_workers: Map.put(state.busy_workers, worker, {ref, from_pid})
        }

        {:reply, {:ok, ref}, new_state}

      total_queue_length(state) < state.max_queue ->
        updated_queues =
          Map.update!(state.queues, priority, fn q -> :queue.in(task, q) end)

        {:reply, {:ok, ref}, %{state | queues: updated_queues}}

      true ->
        {:reply, {:error, :queue_full}, state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      busy_workers: map_size(state.busy_workers),
      idle_workers: length(state.idle_workers),
      queue_high: :queue.len(state.queues.high),
      queue_normal: :queue.len(state.queues.normal),
      queue_low: :queue.len(state.queues.low),
      total_queue_length: total_queue_length(state)
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
          send(client_pid, {ref, :error, {:task_crashed, reason}})
          %{state | busy_workers: updated_busy}

        {nil, _} ->
          %{state | idle_workers: List.delete(state.idle_workers, pid)}
      end

    {:ok, new_pid} = start_worker(state.sup)
    new_mref = Process.monitor(new_pid)

    final_state = %{state | monitors: Map.put(new_monitors, new_mref, new_pid)}
    {:noreply, dispatch_next(final_state, new_pid)}
  end

  @impl true
  def handle_info(:promote_stale_tasks, state) do
    now = System.monotonic_time(:millisecond)
    threshold = state.promote_after_ms

    # Promote low → normal
    {promoted_from_low, remaining_low} =
      partition_stale(state.queues.low, now, threshold)

    # Promote normal → high
    {promoted_from_normal, remaining_normal} =
      partition_stale(state.queues.normal, now, threshold)

    # Merge promoted tasks into their target queues (append to back to keep FIFO among promoted)
    new_normal = enqueue_all(remaining_normal, promoted_from_low)
    new_high = enqueue_all(state.queues.high, promoted_from_normal)

    new_queues = %{high: new_high, normal: new_normal, low: remaining_low}

    schedule_promotion(threshold)
    {:noreply, %{state | queues: new_queues}}
  end

  ## --- Private Helpers ---

  defp start_worker(sup) do
    DynamicSupervisor.start_child(sup, {PriorityWorkerPool.Worker, [self()]})
  end

  defp total_queue_length(state) do
    state.queues
    |> Map.values()
    |> Enum.map(&:queue.len/1)
    |> Enum.sum()
  end

  defp dispatch_next(state, worker) do
    case dequeue_highest(state.queues) do
      {:ok, {ref, client_pid, func, _enqueued_at}, new_queues} ->
        send(worker, {:run, {ref, client_pid, func}})

        %{
          state
          | queues: new_queues,
            busy_workers: Map.put(state.busy_workers, worker, {ref, client_pid})
        }

      :empty ->
        %{
          state
          | idle_workers: [worker | state.idle_workers],
            busy_workers: Map.delete(state.busy_workers, worker)
        }
    end
  end

  defp dequeue_highest(queues) do
    Enum.reduce_while([:high, :normal, :low], :empty, fn priority, _acc ->
      case :queue.out(queues[priority]) do
        {{:value, task}, remaining} ->
          {:halt, {:ok, task, Map.put(queues, priority, remaining)}}

        {:empty, _} ->
          {:cont, :empty}
      end
    end)
  end

  defp partition_stale(queue, now, threshold) do
    list = :queue.to_list(queue)

    {stale, fresh} =
      Enum.split_with(list, fn {_ref, _pid, _func, enqueued_at} ->
        now - enqueued_at >= threshold
      end)

    {stale, :queue.from_list(fresh)}
  end

  defp enqueue_all(queue, items) do
    Enum.reduce(items, queue, fn item, q -> :queue.in(item, q) end)
  end

  defp schedule_promotion(interval_ms) do
    Process.send_after(self(), :promote_stale_tasks, interval_ms)
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
