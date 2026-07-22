defmodule PriorityQueue do
  @moduledoc """
  A priority-based task processing `GenServer`.

  Tasks are enqueued with one of three priority levels — `:high`, `:normal`,
  or `:low` — and are always processed highest-priority-first. Within a single
  priority level, tasks are processed in FIFO (enqueue) order.

  Only one task is processed at a time. Each task is run by applying the
  configured processor function inside a separate, monitored process spawned
  via `spawn_monitor/1`, so the `GenServer` loop itself never blocks. This
  keeps `enqueue/3`, `status/1`, and `drain/1` responsive even while a
  long-running or blocking task is executing.

  Processing is driven entirely by internal `:process_next` messages: when a
  task is enqueued while the processor is idle, the server messages itself to
  begin; when a running task finishes and more work remains, it messages
  itself again to continue.

  The result of every processed task is recorded and can be retrieved (in
  processing order) via `processed/1`.
  """

  use GenServer

  @typedoc "Supported priority levels, ordered high > normal > low."
  @type priority :: :high | :normal | :low

  # Priority levels ordered from highest to lowest.
  @levels [:high, :normal, :low]

  defstruct queues: %{high: :queue.new(), normal: :queue.new(), low: :queue.new()},
            processor: nil,
            busy: false,
            processed: [],
            drainers: []

  # ------------------------------------------------------------------
  # Public API
  # ------------------------------------------------------------------

  @doc """
  Starts the priority queue process.

  ## Options

    * `:name` - optional name for process registration.
    * `:processor` - a single-arity function invoked to process each task.
      Defaults to the identity function `fn task -> task end`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Enqueues `task` at the given `priority` (`:high`, `:normal`, or `:low`).

  Triggers processing if the processor is currently idle. Always returns `:ok`.
  """
  @spec enqueue(GenServer.server(), term(), priority()) :: :ok
  def enqueue(server, task, priority) when priority in @levels do
    GenServer.cast(server, {:enqueue, task, priority})
  end

  @doc """
  Returns a map of pending task counts per priority level.

  Only tasks that have not yet started processing are counted, e.g.
  `%{high: 0, normal: 2, low: 1}`.
  """
  @spec status(GenServer.server()) :: %{priority() => non_neg_integer()}
  def status(server) do
    GenServer.call(server, :status)
  end

  @doc """
  Blocks until all currently enqueued tasks have been processed and the queue
  is empty. Returns `:ok`.
  """
  @spec drain(GenServer.server()) :: :ok
  def drain(server) do
    GenServer.call(server, :drain, :infinity)
  end

  @doc """
  Returns the processing history as a list of `{task, result}` tuples, in the
  order the tasks were processed.
  """
  @spec processed(GenServer.server()) :: [{term(), term()}]
  def processed(server) do
    GenServer.call(server, :processed)
  end

  # ------------------------------------------------------------------
  # GenServer callbacks
  # ------------------------------------------------------------------

  @impl true
  @spec init(keyword()) :: {:ok, %__MODULE__{}}
  def init(opts) do
    processor = Keyword.get(opts, :processor, fn task -> task end)
    {:ok, %__MODULE__{processor: processor}}
  end

  @impl true
  def handle_cast({:enqueue, task, priority}, state) do
    queue = :queue.in(task, Map.fetch!(state.queues, priority))
    state = %{state | queues: Map.put(state.queues, priority, queue)}

    if state.busy do
      {:noreply, state}
    else
      send(self(), :process_next)
      {:noreply, %{state | busy: true}}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    counts =
      Map.new(@levels, fn level ->
        {level, :queue.len(Map.fetch!(state.queues, level))}
      end)

    {:reply, counts, state}
  end

  def handle_call(:processed, _from, state) do
    {:reply, Enum.reverse(state.processed), state}
  end

  def handle_call(:drain, from, state) do
    if idle?(state) do
      {:reply, :ok, state}
    else
      {:noreply, %{state | drainers: [from | state.drainers]}}
    end
  end

  @impl true
  def handle_info(:process_next, state) do
    case take_next(state) do
      :empty ->
        {:noreply, notify_drainers(%{state | busy: false})}

      {:ok, task, state} ->
        parent = self()
        processor = state.processor

        {_pid, ref} =
          spawn_monitor(fn ->
            result = processor.(task)
            send(parent, {:task_result, self(), task, result})
          end)

        {:noreply, %{state | busy: true, current: {ref, task}}}
    end
  end

  def handle_info({:task_result, _pid, task, result}, state) do
    state = %{state | processed: [{task, result} | state.processed]}
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    state = record_down(state, ref, reason)
    send(self(), :process_next)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ------------------------------------------------------------------
  # Internal helpers
  # ------------------------------------------------------------------

  # Adds a struct field for the currently-running task at compile time.
  @enforce_keys []
  Module.register_attribute(__MODULE__, :__dummy__, persist: false)

  @spec take_next(%__MODULE__{}) :: :empty | {:ok, term(), %__MODULE__{}}
  defp take_next(state) do
    Enum.reduce_while(@levels, :empty, fn level, _acc ->
      queue = Map.fetch!(state.queues, level)

      case :queue.out(queue) do
        {{:value, task}, rest} ->
          new_state = %{state | queues: Map.put(state.queues, level, rest)}
          {:halt, {:ok, task, new_state}}

        {:empty, _} ->
          {:cont, :empty}
      end
    end)
  end

  # Records a failed task result when the worker crashed before replying.
  @spec record_down(%__MODULE__{}, reference(), term()) :: %__MODULE__{}
  defp record_down(state, ref, reason) do
    case Map.get(state, :current) do
      {^ref, task} ->
        already_recorded? = match?([{^task, _} | _], state.processed)

        processed =
          if reason == :normal or already_recorded? do
            state.processed
          else
            [{task, {:error, reason}} | state.processed]
          end

        %{state | processed: processed, current: nil}

      _ ->
        state
    end
  end

  @spec idle?(%__MODULE__{}) :: boolean()
  defp idle?(state) do
    not state.busy and Enum.all?(@levels, fn level ->
      :queue.is_empty(Map.fetch!(state.queues, level))
    end)
  end

  @spec notify_drainers(%__MODULE__{}) :: %__MODULE__{}
  defp notify_drainers(state) do
    if idle?(state) do
      Enum.each(state.drainers, fn from -> GenServer.reply(from, :ok) end)
      %{state | drainers: []}
    else
      state
    end
  end
end