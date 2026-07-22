defmodule ConcurrentPriorityQueue do
  @moduledoc """
  A `GenServer` that processes tasks according to priority with bounded concurrency.

  Tasks are enqueued with one of three priority levels — `:critical`, `:normal` or
  `:low` — and are processed by a configurable `:processor` function. At most
  `:max_concurrency` tasks are processed simultaneously.

  ## Scheduling

  Whenever a concurrency slot is free, the queue picks the highest priority pending
  task (`:critical` > `:normal` > `:low`). Within a single priority level, tasks are
  started in FIFO order.

  ## Processing model

  Processing happens through internal message passing:

    * `enqueue/3` stores the task and, if `active_count < max_concurrency`, the server
      sends itself a `:process_next` message.
    * Handling `:process_next` pops the next task and runs the processor inside a
      spawned, monitored process. The worker sends `{:result, self(), result}` back and
      then exits.
    * The `{:DOWN, ...}` message for that worker frees the slot and, if more tasks are
      pending, the server sends itself another `:process_next` message.

  Active workers are tracked in a map of `{pid, monitor_ref} => task`, which is how a
  finished worker is associated back to the task it was running.

  ## Example

      {:ok, pid} = ConcurrentPriorityQueue.start_link(max_concurrency: 2,
                                                     processor: &String.upcase/1)
      :ok = ConcurrentPriorityQueue.enqueue(pid, "a", :low)
      :ok = ConcurrentPriorityQueue.enqueue(pid, "b", :critical)
      :ok = ConcurrentPriorityQueue.drain(pid)
      ConcurrentPriorityQueue.processed(pid)
      #=> [{"b", "B"}, {"a", "A"}]
  """

  use GenServer

  @priorities [:critical, :normal, :low]

  @typedoc "A supported priority level."
  @type priority :: :critical | :normal | :low

  @typedoc "Anything can be a task; it is passed verbatim to the processor function."
  @type task :: term()

  @typedoc "A running or registered queue."
  @type server :: GenServer.server()

  defmodule State do
    @moduledoc false

    defstruct processor: nil,
              max_concurrency: 1,
              queues: %{},
              active: %{},
              results: %{},
              processed: [],
              drainers: []
  end

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the priority queue process.

  ## Options

    * `:name` — optional name used for process registration.
    * `:processor` — single-arity function invoked for each task.
      Defaults to `fn task -> task end`.
    * `:max_concurrency` — maximum number of tasks processed simultaneously.
      Must be a positive integer. Defaults to `1`.

  Raises `ArgumentError` when `:max_concurrency` is not a positive integer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    processor = Keyword.get(opts, :processor, fn task -> task end)
    max_concurrency = Keyword.get(opts, :max_concurrency, 1)

    unless is_function(processor, 1) do
      raise ArgumentError,
            ":processor must be a function of arity 1, got: #{inspect(processor)}"
    end

    unless is_integer(max_concurrency) and max_concurrency > 0 do
      raise ArgumentError,
            ":max_concurrency must be a positive integer, got: #{inspect(max_concurrency)}"
    end

    init_arg = %{processor: processor, max_concurrency: max_concurrency}

    case Keyword.fetch(opts, :name) do
      {:ok, name} -> GenServer.start_link(__MODULE__, init_arg, name: name)
      :error -> GenServer.start_link(__MODULE__, init_arg)
    end
  end

  @doc """
  Enqueues `task` at the given `priority`.

  Triggers processing immediately when a concurrency slot is available. Always
  returns `:ok`.
  """
  @spec enqueue(server(), task(), priority()) :: :ok
  def enqueue(server, task, priority) when priority in @priorities do
    GenServer.call(server, {:enqueue, task, priority})
  end

  @doc """
  Returns a map with the pending task count per priority level, the number of tasks
  currently being processed and the configured max concurrency.

  Pending counts only include tasks that have not started processing yet.

      %{critical: 0, normal: 2, low: 1, active: 3, max_concurrency: 5}
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
  Blocks until every enqueued task has been processed — the pending queues are empty
  and no task is actively being processed. Returns `:ok`.
  """
  @spec drain(server(), timeout()) :: :ok
  def drain(server, timeout \\ :infinity) do
    GenServer.call(server, :drain, timeout)
  end

  @doc """
  Returns the list of `{task, result}` tuples in the order the tasks finished
  processing. With `max_concurrency > 1` the completion order may differ from the
  order in which tasks were started.
  """
  @spec processed(server()) :: [{task(), term()}]
  def processed(server) do
    GenServer.call(server, :processed)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(%{processor: processor, max_concurrency: max_concurrency}) do
    state = %State{
      processor: processor,
      max_concurrency: max_concurrency,
      queues: Map.new(@priorities, fn priority -> {priority, :queue.new()} end),
      active: %{},
      results: %{},
      processed: [],
      drainers: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:enqueue, task, priority}, _from, state) do
    queue = :queue.in(task, Map.fetch!(state.queues, priority))
    state = %{state | queues: Map.put(state.queues, priority, queue)}

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
      {:noreply, %{state | drainers: [from | state.drainers]}}
    end
  end

  def handle_call(:processed, _from, state) do
    {:reply, Enum.reverse(state.processed), state}
  end

  @impl true
  def handle_info(:process_next, state) do
    case {slot_available?(state), pop_next(state)} do
      {true, {:ok, task, state}} ->
        {:noreply, start_worker(state, task)}

      _otherwise ->
        {:noreply, state}
    end
  end

  def handle_info({:result, pid, result}, state) do
    {:noreply, %{state | results: Map.put(state.results, pid, result)}}
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    key = {pid, ref}

    case Map.pop(state.active, key) do
      {nil, _active} ->
        {:noreply, state}

      {task, active} ->
        {result, results} = Map.pop(state.results, pid)
        result = if reason == :normal, do: result, else: {:error, reason}

        state = %{
          state
          | active: active,
            results: results,
            processed: [{task, result} | state.processed]
        }

        if slot_available?(state) and pending?(state) do
          send(self(), :process_next)
        end

        {:noreply, maybe_reply_drainers(state)}
    end
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp start_worker(state, task) do
    server = self()
    processor = state.processor

    {pid, ref} =
      spawn_monitor(fn ->
        result = processor.(task)
        send(server, {:result, self(), result})
      end)

    %{state | active: Map.put(state.active, {pid, ref}, task)}
  end

  defp pop_next(state) do
    Enum.reduce_while(@priorities, :empty, fn priority, _acc ->
      queue = Map.fetch!(state.queues, priority)

      case :queue.out(queue) do
        {{:value, task}, rest} ->
          state = %{state | queues: Map.put(state.queues, priority, rest)}
          {:halt, {:ok, task, state}}

        {:empty, _queue} ->
          {:cont, :empty}
      end
    end)
  end

  defp slot_available?(state), do: map_size(state.active) < state.max_concurrency

  defp pending?(state) do
    Enum.any?(@priorities, fn p -> not :queue.is_empty(Map.fetch!(state.queues, p)) end)
  end

  defp idle?(state), do: map_size(state.active) == 0 and not pending?(state)

  defp maybe_reply_drainers(state) do
    if idle?(state) do
      Enum.each(state.drainers, fn from -> GenServer.reply(from, :ok) end)
      %{state | drainers: []}
    else
      state
    end
  end
end