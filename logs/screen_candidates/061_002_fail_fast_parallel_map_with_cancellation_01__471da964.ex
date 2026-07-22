defmodule ConcurrencyCounter do
  @moduledoc """
  A small GenServer that tracks how many units of work are currently active.

  It is primarily a test aid: callers `increment/1` before starting a unit of work and
  `decrement/1` when it finishes. In addition to the live count, the server remembers the
  highest value the counter ever reached (`peak/1`) and how many times `increment/1` was
  ever called (`started/1`).

  The `started/1` figure is useful to assert that queued work was genuinely cancelled after
  a failure: if fewer increments happened than there were elements, some work never began.
  """

  use GenServer

  @type server :: GenServer.server()

  defstruct active: 0, peak: 0, started: 0

  @doc """
  Starts the counter.

  Accepts the usual `GenServer` options; `:name` is the interesting one for tests.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, _rest} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, :ok, gen_opts)
  end

  @doc """
  Increments the active count and returns the new value.
  """
  @spec increment(server()) :: non_neg_integer()
  def increment(server) do
    GenServer.call(server, :increment)
  end

  @doc """
  Decrements the active count and returns the new value.
  """
  @spec decrement(server()) :: integer()
  def decrement(server) do
    GenServer.call(server, :decrement)
  end

  @doc """
  Returns the highest value the active count has ever reached.
  """
  @spec peak(server()) :: non_neg_integer()
  def peak(server) do
    GenServer.call(server, :peak)
  end

  @doc """
  Returns how many times `increment/1` has been called on this counter.
  """
  @spec started(server()) :: non_neg_integer()
  def started(server) do
    GenServer.call(server, :started)
  end

  @doc """
  Stops the counter process.
  """
  @spec stop(server()) :: :ok
  def stop(server) do
    GenServer.stop(server)
  end

  @impl true
  def init(:ok) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call(:increment, _from, state) do
    active = state.active + 1
    peak = max(state.peak, active)
    state = %{state | active: active, peak: peak, started: state.started + 1}
    {:reply, active, state}
  end

  def handle_call(:decrement, _from, state) do
    active = state.active - 1
    {:reply, active, %{state | active: active}}
  end

  def handle_call(:peak, _from, state) do
    {:reply, state.peak, state}
  end

  def handle_call(:started, _from, state) do
    {:reply, state.started, state}
  end
end

defmodule FailFastMap do
  @moduledoc """
  Parallel map with a concurrency limit and fail-fast semantics.

  `pmap/3` applies a function to every element of a collection, running at most
  `max_concurrency` tasks at any one time. Unlike a "collect every error" parallel map, the
  first failure wins: as soon as any element raises or its worker exits abnormally, all
  still-running workers are killed, no queued element is ever started, and the caller gets
  `{:error, {index, reason}}` back.

  The scheduling is implemented directly on top of `spawn_monitor/1` and `Process.exit/2`
  rather than `Task.async_stream/3`, so the cancellation behaviour is explicit:

    * workers are spawned monitored and send their result back to the caller;
    * the caller loops on `:DOWN` and result messages, topping the running window back up to
      `max_concurrency` each time a worker finishes successfully;
    * on the first failure the caller stops pulling from the queue, kills every live worker
      with `Process.exit(pid, :kill)`, drains their monitors, and returns.

  ## Examples

      iex> FailFastMap.pmap([1, 2, 3], fn n -> n * 2 end, 2)
      {:ok, [2, 4, 6]}

      iex> FailFastMap.pmap([], fn n -> n end, 4)
      {:ok, []}

      iex> {:error, {index, {exception, _stacktrace}}} =
      ...>   FailFastMap.pmap([1, 2, 3], fn
      ...>     2 -> raise "boom"
      ...>     n -> n
      ...>   end, 1)
      iex> {index, exception.message}
      {1, "boom"}

  """

  @typedoc "Zero-based position of an element in the input collection."
  @type index :: non_neg_integer()

  @typedoc """
  Why an element failed.

  For a raised exception this is `{exception, stacktrace}`; for a thrown value
  `{:nocatch, value}`; otherwise it is the raw exit reason of the worker process.
  """
  @type reason :: term()

  @doc """
  Applies `func` to each element of `collection` in parallel, fail-fast.

  At most `max_concurrency` worker processes are alive at any moment: a new element is only
  started once a running worker has finished, or while the initial window is still filling.

  Returns `{:ok, results}` with the return values in the same order as the input when every
  element succeeds, and `{:error, {index, reason}}` on the first failure. When a failure is
  detected every still-running worker is killed and no queued element is started.

  An empty collection returns `{:ok, []}` without spawning anything.

  ## Examples

      iex> FailFastMap.pmap(1..5, &(&1 + 1), 3)
      {:ok, [2, 3, 4, 5, 6]}

  """
  @spec pmap(Enumerable.t(), (term() -> term()), pos_integer()) ::
          {:ok, list()} | {:error, {index(), reason()}}
  def pmap(collection, func, max_concurrency)
      when is_function(func, 1) and is_integer(max_concurrency) and max_concurrency > 0 do
    queue = collection |> Enum.to_list() |> Enum.with_index()

    case queue do
      [] ->
        {:ok, []}

      _ ->
        parent = self()
        ref = make_ref()
        {running, rest} = start_window(queue, max_concurrency, parent, ref, func, %{})
        collect(rest, running, %{}, ref, parent, func)
    end
  end

  # Spawns workers until either the window is full or the queue is exhausted.
  # Returns `{running, remaining_queue}` where `running` maps monitor refs to `{pid, index}`.
  @spec start_window(list(), non_neg_integer(), pid(), reference(), (term() -> term()), map()) ::
          {map(), list()}
  defp start_window(queue, 0, _parent, _ref, _func, running), do: {running, queue}
  defp start_window([], _slots, _parent, _ref, _func, running), do: {running, []}

  defp start_window([{element, index} | rest], slots, parent, ref, func, running) do
    {pid, monitor} = spawn_worker(element, index, parent, ref, func)
    running = Map.put(running, monitor, {pid, index})
    start_window(rest, slots - 1, parent, ref, func, running)
  end

  @spec spawn_worker(term(), index(), pid(), reference(), (term() -> term())) ::
          {pid(), reference()}
  defp spawn_worker(element, index, parent, ref, func) do
    spawn_monitor(fn ->
      result =
        try do
          {:ok, func.(element)}
        rescue
          exception -> {:error, {exception, __STACKTRACE__}}
        catch
          :throw, value -> {:error, {:nocatch, value}}
          :exit, reason -> {:error, reason}
        end

      send(parent, {ref, index, result})
    end)
  end

  # Main loop: waits for worker results and monitor messages, refilling the window as slots
  # free up. `results` accumulates successful values keyed by index.
  @spec collect(list(), map(), map(), reference(), pid(), (term() -> term())) ::
          {:ok, list()} | {:error, {index(), reason()}}
  defp collect(queue, running, results, ref, parent, func) do
    if running == %{} do
      {:ok, results |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(&elem(&1, 1))}
    else
      receive do
        {^ref, index, {:ok, value}} ->
          results = Map.put(results, index, value)
          {running, queue} = await_exit(running, index, queue, parent, ref, func)
          collect(queue, running, results, ref, parent, func)

        {^ref, index, {:error, reason}} ->
          shutdown(running)
          {:error, {index, reason}}

        {:DOWN, monitor, :process, _pid, exit_reason} when is_map_key(running, monitor) ->
          {{_pid, index}, running} = Map.pop(running, monitor)
          handle_down(exit_reason, index, running, queue, results, ref, parent, func)
      end
    end
  end

  # A worker sent its result; wait for the matching `:DOWN` so the slot is truly free before
  # spawning a replacement. This is what keeps the live-process count at or below the limit.
  @spec await_exit(map(), index(), list(), pid(), reference(), (term() -> term())) ::
          {map(), list()}
  defp await_exit(running, index, queue, parent, ref, func) do
    monitor =
      Enum.find_value(running, fn {monitor, {_pid, worker_index}} ->
        if worker_index == index, do: monitor
      end)

    case monitor do
      nil ->
        # The `:DOWN` was already consumed; the slot is free.
        refill(running, queue, parent, ref, func)

      monitor ->
        receive do
          {:DOWN, ^monitor, :process, _pid, _reason} ->
            refill(Map.delete(running, monitor), queue, parent, ref, func)
        end
    end
  end

  # A worker went down. If it already reported a result the exit is normal and harmless;
  # otherwise the process died without answering and that is a failure for its element.
  @spec handle_down(
          term(),
          index(),
          map(),
          list(),
          map(),
          reference(),
          pid(),
          (term() -> term())
        ) :: {:ok, list()} | {:error, {index(), reason()}}
  defp handle_down(:normal, index, running, queue, results, ref, parent, func) do
    receive do
      {^ref, ^index, {:ok, value}} ->
        {running, queue} = refill(running, queue, parent, ref, func)
        collect(queue, running, Map.put(results, index, value), ref, parent, func)

      {^ref, ^index, {:error, reason}} ->
        shutdown(running)
        {:error, {index, reason}}
    after
      0 ->
        {running, queue} = refill(running, queue, parent, ref, func)
        collect(queue, running, results, ref, parent, func)
    end
  end

  defp handle_down(exit_reason, index, running, _queue, _results, _ref, _parent, _func) do
    shutdown(running)
    {:error, {index, exit_reason}}
  end

  # Starts at most one queued element, filling the slot that just freed up.
  @spec refill(map(), list(), pid(), reference(), (term() -> term())) :: {map(), list()}
  defp refill(running, [], _parent, _ref, _func), do: {running, []}

  defp refill(running, [{element, index} | rest], parent, ref, func) do
    {pid, monitor} = spawn_worker(element, index, parent, ref, func)
    {Map.put(running, monitor, {pid, index}), rest}
  end

  # Kills every still-running worker and drains its monitor message so the caller's mailbox
  # is left clean.
  @spec shutdown(map()) :: :ok
  defp shutdown(running) do
    Enum.each(running, fn {_monitor, {pid, _index}} -> Process.exit(pid, :kill) end)

    Enum.each(running, fn {monitor, {_pid, _index}} ->
      receive do
        {:DOWN, ^monitor, :process, _pid, _reason} -> :ok
      end
    end)
  end
end