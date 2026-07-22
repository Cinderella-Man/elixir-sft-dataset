defmodule ConcurrentPriorityQueue do
  @moduledoc """
  A `GenServer` that processes tasks according to priority with configurable concurrency.

  Tasks are enqueued with one of three priority levels — `:critical`, `:normal` or `:low` —
  and are started in strict priority order (`:critical` > `:normal` > `:low`). Within a
  single priority level tasks are started in FIFO order.

  Up to `:max_concurrency` tasks may be processed simultaneously. Each task is handed to the
  configured `:processor` function, which runs inside a spawned and monitored process so that
  the queue itself never blocks. When a worker terminates, the queue immediately starts the
  next highest-priority pending task if one is available.

  ## Example

      {:ok, pid} = ConcurrentPriorityQueue.start_link(processor: &String.upcase/1,
                                                      max_concurrency: 4)

      :ok = ConcurrentPriorityQueue.enqueue(pid, "low", :low)
      :ok = ConcurrentPriorityQueue.enqueue(pid, "urgent", :critical)
      :ok = ConcurrentPriorityQueue.drain(pid)

      ConcurrentPriorityQueue.processed(pid)
      #=> [{"urgent", "URGENT"}, {"low", "LOW"}]

  Note that with a concurrency greater than one, the completion order reported by
  `processed/1` may differ from the order in which tasks were started.
  """

  use GenServer

  @priorities [:critical, :normal, :low]

  @typedoc "A priority level accepted by `enqueue/3`."
  @type priority :: :critical | :normal | :low

  @typedoc "An arbitrary term representing a unit of work."
  @type task :: term()

  @typedoc "A server reference accepted by the public API."
  @type server :: GenServer.server()

  defmodule State do
    @moduledoc false

    defstruct processor: nil,
              max_concurrency: 1,
              queues: %{},
              active: %{},
              processed: [],
              drainers: []
  end

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the queue process.

  ## Options

    * `:name` — an optional name under which the process is registered.
    * `:processor` — a single-arity function invoked for each task. Defaults to
      `fn task -> task end`.
    * `:max_concurrency` — the maximum number of tasks processed simultaneously. Must be a
      positive integer. Defaults to `1`.

  Returns `{:ok, pid}` on success, following the usual `GenServer.start_link/3` contract.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Adds `task` to the queue at the given `priority`.

  Processing is triggered immediately if a concurrency slot is free. Always returns `:ok`.
  """
  @spec enqueue(server(), task(), priority()) :: :ok
  def enqueue(server, task, priority) when priority in @priorities do
    GenServer.call(server, {:enqueue, task, priority})
  end

  @doc """
  Returns a map with the number of *pending* (not yet started) tasks per priority level, the
  number of tasks currently being processed and the configured maximum concurrency.

  For example: `%{critical: 0, normal: 2, low: 1, active: 3, max_concurrency: 5}`.
  """
  @spec status(server()) :: %{
          critical: non_neg_integer(),
          normal: non_neg_integer(),
          low: non_neg_integer(),
          active: non_neg_integer(),
          max_concurrency: pos_integer()
        }
  def status(server) do
    GenServer.call(server, :status)
  end

  @doc """
  Blocks until every enqueued task has finished processing.

  Returns `:ok` once the pending queues are empty and no task is actively being processed.
  """
  @spec drain(server()) :: :ok
  def drain(server) do
    GenServer.call(server, :drain, :infinity)
  end

  @doc """
  Returns the list of `{task, result}` tuples in the order the tasks *finished* processing.
  """
  @spec processed(server()) :: [{task(), term()}]
  def processed(server) do
    GenServer.call(server, :processed)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    processor = Keyword.get(opts, :processor, fn task -> task end)
    max_concurrency = Keyword.get(opts, :max_concurrency, 1)

    cond do
      not is_function(processor, 1) ->
        {:stop, {:invalid_option, :processor}}

      not (is_integer(max_concurrency) and max_concurrency > 0) ->
        {:stop, {:invalid_option, :max_concurrency}}

      true ->
        state = %State{
          processor: processor,
          max_concurrency: max_concurrency,
          queues: Map.new(@priorities, fn priority -> {priority, :queue.new()} end),
          active: %{},
          processed: [],
          drainers: []
        }

        {:ok, state}
    end
  end

  @impl GenServer
  def handle_call({:enqueue, task, priority}, _from, state) do
    queue = :queue.in(task, Map.fetch!(state.queues, priority))
    state = %State{state | queues: Map.put(state.queues, priority, queue)}

    if slot_available?(state) do
      send(self(), :process_next)
    end

    {:reply, :ok, state}
  end

  def handle_call(:status, _from, state) do
    counts = Map.new(@priorities, fn p -> {p, :queue.len(Map.fetch!(state.queues, p))} end)

    status =
      counts
      |> Map.put(:active, map_size(state.active))
      |> Map.put(:max_concurrency, state.max_concurrency)

    {:reply, status, state}
  end

  def handle_call(:drain, from, state) do
    if idle?(state) do
      {:reply, :ok, state}
    else
      {:noreply, %State{state | drainers: [from | state.drainers]}}
    end
  end

  def handle_call(:processed, _from, state) do
    {:reply, Enum.reverse(state.processed), state}
  end

  @impl GenServer
  def handle_info(:process_next, state) do
    {:noreply, maybe_start_next(state)}
  end

  def handle_info({:task_result, ref, result}, state) do
    state =
      case Enum.find(state.active, fn {{_pid, mref}, _task} -> mref == ref end) do
        {key, task} ->
          %State{
            state
            | active: Map.put(state.active, key, {:done, task, result})
          }

        nil ->
          state
      end

    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    case Map.pop(state.active, {pid, ref}) do
      {nil, _active} ->
        {:noreply, state}

      {entry, active} ->
        state = %State{state | active: active, processed: record(entry, reason, state.processed)}
        state = maybe_start_next(state)
        {:noreply, maybe_notify_drainers(state)}
    end
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  @spec record(term(), term(), [{task(), term()}]) :: [{task(), term()}]
  defp record({:done, task, result}, _reason, processed), do: [{task, result} | processed]
  defp record(task, reason, processed), do: [{task, {:error, reason}} | processed]

  @spec slot_available?(State.t()) :: boolean()
  defp slot_available?(state), do: map_size(state.active) < state.max_concurrency

  @spec idle?(State.t()) :: boolean()
  defp idle?(state), do: map_size(state.active) == 0 and pending_count(state) == 0

  @spec pending_count(State.t()) :: non_neg_integer()
  defp pending_count(state) do
    Enum.reduce(@priorities, 0, fn p, acc -> acc + :queue.len(Map.fetch!(state.queues, p)) end)
  end

  @spec maybe_start_next(State.t()) :: State.t()
  defp maybe_start_next(state) do
    if slot_available?(state) do
      case pop_highest(state) do
        {:empty, state} ->
          state

        {{:value, task}, state} ->
          state = start_worker(state, task)

          if slot_available?(state) and pending_count(state) > 0 do
            send(self(), :process_next)
          end

          state
      end
    else
      state
    end
  end

  @spec pop_highest(State.t()) :: {:empty | {:value, task()}, State.t()}
  defp pop_highest(state) do
    Enum.reduce_while(@priorities, {:empty, state}, fn priority, acc ->
      queue = Map.fetch!(state.queues, priority)

      case :queue.out(queue) do
        {{:value, task}, rest} ->
          queues = Map.put(state.queues, priority, rest)
          {:halt, {{:value, task}, %State{state | queues: queues}}}

        {:empty, _queue} ->
          {:cont, acc}
      end
    end)
  end

  @spec start_worker(State.t(), task()) :: State.t()
  defp start_worker(state, task) do
    parent = self()
    processor = state.processor

    {pid, ref} =
      spawn_monitor(fn ->
        ref = :erlang.monitor(:process, parent)
        result = processor.(task)
        :erlang.demonitor(ref, [:flush])
        send(parent, {:task_result, self_monitor_ref(), result})
      end)

    # The worker cannot know the monitor reference held by the parent, so the parent stores
    # the mapping and the worker reports its result keyed by that same reference below.
    send(pid, {:monitor_ref, ref})

    %State{state | active: Map.put(state.active, {pid, ref}, task)}
  end

  @spec self_monitor_ref() :: reference()
  defp self_monitor_ref do
    receive do
      {:monitor_ref, ref} -> ref
    after
      5_000 -> make_ref()
    end
  end

  @spec maybe_notify_drainers(State.t()) :: State.t()
  defp maybe_notify_drainers(state) do
    if idle?(state) do
      Enum.each(state.drainers, fn from -> GenServer.reply(from, :ok) end)
      %State{state | drainers: []}
    else
      state
    end
  end
end