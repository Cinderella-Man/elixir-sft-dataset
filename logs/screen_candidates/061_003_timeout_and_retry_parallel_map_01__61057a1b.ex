defmodule ConcurrencyCounter do
  @moduledoc """
  A tiny GenServer that tracks how many things are currently "active" and the
  highest value that count has ever reached.

  It is intended as a test aid: increment when a unit of work starts, decrement
  when it finishes, then assert that `peak/1` never exceeded the configured
  concurrency limit.

      {:ok, counter} = ConcurrencyCounter.start_link(name: :my_counter)
      ConcurrencyCounter.increment(:my_counter)
      ConcurrencyCounter.decrement(:my_counter)
      ConcurrencyCounter.peak(:my_counter)
      #=> 1

  All operations are synchronous calls, so the count and the peak are always
  consistent with respect to the callers that have already returned.
  """

  use GenServer

  @type server :: GenServer.server()

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the counter.

  Accepts the usual `GenServer` options; `:name` is the interesting one. The
  counter starts at `0` with a peak of `0`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Increments the active count and returns the new value.

  Updates the recorded peak if the new value is the highest seen so far.
  """
  @spec increment(server()) :: integer()
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
  @spec peak(server()) :: integer()
  def peak(server) do
    GenServer.call(server, :peak)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(_opts) do
    {:ok, %{count: 0, peak: 0}}
  end

  @impl GenServer
  def handle_call(:increment, _from, %{count: count, peak: peak} = state) do
    new_count = count + 1
    new_peak = max(peak, new_count)
    {:reply, new_count, %{state | count: new_count, peak: new_peak}}
  end

  def handle_call(:decrement, _from, %{count: count} = state) do
    new_count = count - 1
    {:reply, new_count, %{state | count: new_count}}
  end

  def handle_call(:peak, _from, %{peak: peak} = state) do
    {:reply, peak, state}
  end
end

defmodule RetryMap do
  @moduledoc """
  Parallel `map` with a hard concurrency cap, a per-attempt timeout, and bounded
  retries — built directly on `spawn_monitor/1`, `Process.send_after/3` and
  `Process.exit/2` (no `Task.async_stream`).

  `pmap/3` walks the collection, giving each element a "slot" in a pool of at
  most `:max_concurrency` live tasks. Results come back in the original order,
  each tagged:

    * `{:ok, value}` — an attempt returned `value` within `:timeout`
    * `{:error, :timeout}` — every attempt (up to `:max_attempts`) timed out
    * `{:error, {:exception, reason}}` — the worker raised; `reason` is the
      exception struct
    * `{:error, {:exit, reason}}` — the worker exited abnormally for some other
      reason (a bare `exit/1`, a `throw`, a killed process, ...)

  ## Semantics

  Timeouts are *transient*: the attempt is killed and, if attempts remain, the
  element is retried in the very same slot, so a retry never pushes the number
  of live tasks above the limit. Crashes are *permanent*: the element fails
  immediately with no retry. Neither a crash nor a timeout in one element can
  affect any other element — every worker is an isolated, monitored process and
  the scheduler traps nothing but its own monitor messages.

  ## Options

    * `:max_concurrency` — maximum number of tasks alive at once (default `5`)
    * `:timeout` — per-attempt timeout in milliseconds (default `5000`)
    * `:max_attempts` — maximum number of attempts per element (default `1`)

  ## Examples

      iex> RetryMap.pmap([1, 2, 3], fn n -> n * 2 end, max_concurrency: 2)
      [ok: 2, ok: 4, ok: 6]

      iex> RetryMap.pmap([1], fn _ -> Process.sleep(:infinity) end, timeout: 10)
      [error: :timeout]

  """

  @default_max_concurrency 5
  @default_timeout 5_000
  @default_max_attempts 1

  @type result :: {:ok, term()} | {:error, error_reason()}
  @type error_reason :: :timeout | {:exception, Exception.t()} | {:exit, term()}

  # A slot currently running an attempt for one element.
  #
  #   index    — position of the element in the input, used to reassemble order
  #   element  — the element itself, kept so a retry can re-run `func` on it
  #   pid/ref  — the monitored worker process for the current attempt
  #   timer    — the `Process.send_after/3` reference for this attempt
  #   attempts — how many attempts have been *started* for this element so far
  #
  # `running` maps the worker's monitor ref to this struct, so both the `:DOWN`
  # message and the timeout message can find their slot in constant time.

  @doc """
  Applies `func` to every element of `collection` in parallel and returns the
  tagged results in the original order.

  At most `opts[:max_concurrency]` worker processes are alive at any instant. A
  freed slot is refilled from the queue as soon as an element reaches a terminal
  result; a retry of a timed-out element reuses that element's own slot, so the
  cap holds across retries too.

  Options: `:max_concurrency` (default `#{@default_max_concurrency}`), `:timeout`
  in milliseconds (default `#{@default_timeout}`), and `:max_attempts` (default
  `#{@default_max_attempts}`).

  ## Examples

      iex> RetryMap.pmap([1, 2, 3], fn n -> n + 1 end, [])
      [ok: 2, ok: 3, ok: 4]

      iex> [{:error, {:exception, %RuntimeError{}}}, {:ok, 2}] =
      ...>   RetryMap.pmap([1, 2], fn
      ...>     1 -> raise "boom"
      ...>     n -> n
      ...>   end, max_attempts: 3)
      ...> :ok
      :ok

  """
  @spec pmap(Enumerable.t(), (term() -> term()), keyword()) :: [result()]
  def pmap(collection, func, opts \\ []) when is_function(func, 1) and is_list(opts) do
    max_concurrency = positive_int(opts, :max_concurrency, @default_max_concurrency)
    max_attempts = positive_int(opts, :max_attempts, @default_max_attempts)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    queue =
      collection
      |> Enum.to_list()
      |> Enum.with_index()

    total = length(queue)

    if total == 0 do
      []
    else
      state = %{
        func: func,
        timeout: timeout,
        max_attempts: max_attempts,
        queue: queue,
        running: %{},
        results: %{},
        remaining: total
      }

      state
      |> fill_slots(max_concurrency)
      |> loop()
      |> collect(total)
    end
  end

  # ---------------------------------------------------------------------------
  # Scheduler
  # ---------------------------------------------------------------------------

  # Start attempts until either the queue is empty or the pool is full.
  defp fill_slots(state, max_concurrency) do
    if map_size(state.running) < max_concurrency do
      case state.queue do
        [] ->
          state

        [{element, index} | rest] ->
          %{state | queue: rest}
          |> start_attempt(element, index, 0)
          |> fill_slots(max_concurrency)
      end
    else
      state
    end
  end

  # Spawn a monitored worker for one attempt and arm its timeout timer.
  defp start_attempt(state, element, index, attempts) do
    parent = self()
    func = state.func

    {pid, ref} =
      spawn_monitor(fn ->
        # Exceptions/throws/exits propagate as an abnormal `:DOWN` reason, which
        # the scheduler classifies as a permanent failure.
        send(parent, {:result, self(), func.(element)})
      end)

    timer = Process.send_after(self(), {:timeout, ref}, state.timeout)

    slot = %{
      index: index,
      element: element,
      pid: pid,
      timer: timer,
      attempts: attempts + 1
    }

    %{state | running: Map.put(state.running, ref, slot)}
  end

  # The main receive loop: runs until every element has a terminal result.
  defp loop(%{remaining: 0} = state), do: state

  defp loop(state) do
    receive do
      {:result, pid, value} ->
        state
        |> find_slot_by_pid(pid)
        |> case do
          nil ->
            # A late reply from an attempt we already killed; ignore it.
            loop(state)

          {ref, slot} ->
            state
            |> cleanup_slot(ref, slot, :demonitor)
            |> finish(slot, {:ok, value})
            |> loop()
        end

      {:DOWN, ref, :process, _pid, reason} ->
        case Map.fetch(state.running, ref) do
          :error ->
            # `:DOWN` for a slot already resolved (normal exit after `:result`,
            # or a kill we initiated); nothing to do.
            loop(state)

          {:ok, slot} ->
            state
            |> cleanup_slot(ref, slot, :skip_demonitor)
            |> handle_down(slot, reason)
            |> loop()
        end

      {:timeout, ref} ->
        case Map.fetch(state.running, ref) do
          :error ->
            # Timer fired after the element already finished; ignore.
            loop(state)

          {:ok, slot} ->
            state
            |> kill_attempt(ref, slot)
            |> handle_timeout(slot)
            |> loop()
        end
    end
  end

  # A worker went down before sending a result.
  #
  # `:normal` here means the worker exited without ever sending `{:result, ...}`,
  # which we treat as an abnormal exit rather than silently hanging.
  defp handle_down(state, slot, reason) do
    finish(state, slot, {:error, classify_exit(reason)})
  end

  # An attempt blew its deadline: retry in the same slot if attempts remain.
  defp handle_timeout(state, slot) do
    if slot.attempts < state.max_attempts do
      start_attempt(state, slot.element, slot.index, slot.attempts)
    else
      finish(state, slot, {:error, :timeout})
    end
  end

  # Record a terminal result for an element and pull the next element (if any)
  # into the now-free slot.
  defp finish(state, slot, result) do
    state = %{
      state
      | results: Map.put(state.results, slot.index, result),
        remaining: state.remaining - 1
    }

    case state.queue do
      [] ->
        state

      [{element, index} | rest] ->
        %{state | queue: rest}
        |> start_attempt(element, index, 0)
    end
  end

  # ---------------------------------------------------------------------------
  # Slot bookkeeping
  # ---------------------------------------------------------------------------

  defp find_slot_by_pid(state, pid) do
    Enum.find_value(state.running, fn {ref, slot} ->
      if slot.pid == pid, do: {ref, slot}
    end)
  end

  # Drop a slot from the pool: cancel its timer, flush stale messages, and (when
  # we are not already handling its `:DOWN`) demonitor the worker.
  defp cleanup_slot(state, ref, slot, demonitor) do
    Process.cancel_timer(slot.timer)

    case demonitor do
      :demonitor -> Process.demonitor(ref, [:flush])
      :skip_demonitor -> :ok
    end

    flush_timeout(ref)
    %{state | running: Map.delete(state.running, ref)}
  end

  # Kill a timed-out attempt and remove it from the pool. `:flush` on the
  # demonitor guarantees we never see its `:DOWN`, and we drain any `{:result,
  # ...}` it may have raced in just before dying.
  defp kill_attempt(state, ref, slot) do
    Process.demonitor(ref, [:flush])
    Process.exit(slot.pid, :kill)
    flush_result(slot.pid)
    %{state | running: Map.delete(state.running, ref)}
  end

  defp flush_timeout(ref) do
    receive do
      {:timeout, ^ref} -> :ok
    after
      0 -> :ok
    end
  end

  defp flush_result(pid) do
    receive do
      {:result, ^pid, _value} -> :ok
    after
      0 -> :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # `spawn_monitor` reports a raise as `{exception, stacktrace}`; anything else
  # (a bare `exit/1`, a `throw`, `:killed`, ...) is reported as-is.
  defp classify_exit({%{__struct__: _} = maybe_exception, stacktrace} = reason)
       when is_list(stacktrace) do
    if Exception.exception?(maybe_exception) do
      {:exception, maybe_exception}
    else
      {:exit, reason}
    end
  end

  defp classify_exit(reason), do: {:exit, reason}

  defp positive_int(opts, key, default) do
    case Keyword.get(opts, key, default) do
      value when is_integer(value) and value > 0 -> value
      other -> raise ArgumentError, "#{inspect(key)} must be a positive integer, got: " <>
                                      inspect(other)
    end
  end

  defp collect(state, total) do
    Enum.map(0..(total - 1), fn index -> Map.fetch!(state.results, index) end)
  end
end