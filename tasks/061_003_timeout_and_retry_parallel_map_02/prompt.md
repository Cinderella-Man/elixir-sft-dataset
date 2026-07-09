Implement the private `loop/4` function — the heart of `RetryMap.pmap/3`'s scheduler.

`loop(running, queue, cfg, results)` is the main receive loop that drives every in-flight
attempt to a terminal result while keeping the concurrency limit and retry budget honest.
Its arguments are:

  * `running` — a map keyed by a per-attempt `ref` to the bookkeeping tuple produced by
    `start_attempt/6`, namely `{pid, mon, idx, elem, attempts_left, timer}`.
  * `queue` — the list of not-yet-started elements, each shaped `{elem, idx, attempts}`.
  * `cfg` — a config map `%{func: func, timeout: timeout}`.
  * `results` — a map from element index (`idx`) to that element's tagged result.

Behavior:

  * **Base case.** When `running` is empty *and* `queue` is `[]`, there is nothing left to
    do: return `results`.

  * **Otherwise, block on `receive`** and handle these messages:

    - `{ref, {:ok, value}}` for a `ref` currently in `running` — a successful attempt. Look
      up its entry, `cleanup/2` the monitor and timer, delete the ref from `running`, record
      `{:ok, value}` at `idx` in `results`, then `fill/3` a freed slot from the queue and
      recurse.

    - `{ref, {:error, reason}}` for a `ref` in `running` — a **permanent** failure (a raised
      exception, exit, or throw captured by the attempt). Do **not** retry: `cleanup/2`,
      delete the ref, record `{:error, reason}` at `idx`, `fill/3` from the queue, and recurse.

    - `{:timeout, ref}` for a `ref` in `running` — the per-attempt timer fired. `cleanup/2`
      the monitor and timer, `Process.exit(pid, :kill)` the attempt, `drain/1` any result the
      attempt may already have sent for `ref`, and delete the ref from `running`. Decrement
      `attempts_left`. If attempts remain, start a fresh attempt for the *same* element via
      `start_attempt/6` (reusing this element's slot — do **not** pull from the queue), add it
      to `running`, and recurse. If no attempts remain, record `{:error, :timeout}` at `idx`,
      `fill/3` from the queue, and recurse.

    - `{:DOWN, mon, :process, _pid, reason}` — a monitored attempt went down. Find the
      `running` entry whose monitor equals `mon`. If found, cancel its timer, `drain/1` its
      ref, delete it from `running`, record `{:error, {:down, reason}}` at `idx`, `fill/3`
      from the queue, and recurse. If no entry matches (e.g. it was already cleaned up), just
      recurse unchanged.

    - Any other message — ignore it and recurse with state unchanged.

Rely on the existing helpers `start_attempt/6`, `fill/3`, `cleanup/2`, and `drain/1`; do not
reimplement them.

```elixir
defmodule ConcurrencyCounter do
  @moduledoc """
  A GenServer that tracks an active-task count and remembers the highest value
  it has ever reached (the "peak"). Intended for tests to verify that
  `RetryMap.pmap/3` never exceeds its declared concurrency limit at runtime.
  """

  use GenServer

  @doc """
  Starts the counter process.

  Accepts a `:name` option (defaulting to `#{inspect(__MODULE__)}`); any other
  options are forwarded to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, server_opts} =
      case Keyword.pop(opts, :name) do
        {nil, rest} -> {__MODULE__, rest}
        {name, rest} -> {name, rest}
      end

    GenServer.start_link(__MODULE__, %{count: 0, peak: 0}, [{:name, name} | server_opts])
  end

  @doc "Increments the active count and returns the new value."
  @spec increment(GenServer.server()) :: integer()
  def increment(server), do: GenServer.call(server, :increment)

  @doc "Decrements the active count and returns the new value."
  @spec decrement(GenServer.server()) :: integer()
  def decrement(server), do: GenServer.call(server, :decrement)

  @doc "Returns the highest value the counter has ever reached."
  @spec peak(GenServer.server()) :: integer()
  def peak(server), do: GenServer.call(server, :peak)

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call(:increment, _from, %{count: count, peak: peak} = state) do
    new_count = count + 1
    {:reply, new_count, %{state | count: new_count, peak: max(new_count, peak)}}
  end

  def handle_call(:decrement, _from, %{count: count} = state) do
    new_count = count - 1
    {:reply, new_count, %{state | count: new_count}}
  end

  def handle_call(:peak, _from, %{peak: peak} = state), do: {:reply, peak, state}
end

defmodule RetryMap do
  @moduledoc """
  Concurrency-limited parallel map with per-attempt timeouts and bounded retries.

  Each element yields a tagged result: `{:ok, value}` on success,
  `{:error, :timeout}` after exhausting timed-out attempts, or a tagged error
  such as `{:error, {:exception, reason}}` for a permanent (non-retried) crash.
  """

  @doc """
  Applies `func` to each element of `collection` in parallel and returns a list
  of tagged results in the **same order** as the input.

  At most `:max_concurrency` tasks are alive at once. Each attempt is given
  `:timeout` milliseconds; a timed-out attempt is killed and retried up to
  `:max_attempts` total attempts before yielding `{:error, :timeout}`. A raised
  exception (or abnormal exit) is a permanent failure and is not retried.

  ## Options

    * `:max_concurrency` — maximum tasks alive simultaneously (default `5`)
    * `:timeout` — per-attempt timeout in milliseconds (default `5000`)
    * `:max_attempts` — maximum attempts per element (default `1`)
  """
  @spec pmap(Enumerable.t(), (term() -> term()), keyword()) :: [{:ok, term()} | {:error, term()}]
  def pmap(collection, func, opts) when is_function(func, 1) and is_list(opts) do
    max_concurrency = Keyword.get(opts, :max_concurrency, 5)
    timeout = Keyword.get(opts, :timeout, 5000)
    max_attempts = Keyword.get(opts, :max_attempts, 1)

    unless is_integer(max_concurrency) and max_concurrency >= 1,
      do: raise(ArgumentError, ":max_concurrency must be a positive integer")

    unless is_integer(timeout) and timeout >= 0,
      do: raise(ArgumentError, ":timeout must be a non-negative integer")

    unless is_integer(max_attempts) and max_attempts >= 1,
      do: raise(ArgumentError, ":max_attempts must be a positive integer")

    indexed =
      collection
      |> Enum.to_list()
      |> Enum.with_index()
      |> Enum.map(fn {elem, idx} -> {elem, idx, max_attempts} end)

    total = length(indexed)

    if total == 0 do
      []
    else
      cfg = %{func: func, timeout: timeout}
      {seed, queue} = Enum.split(indexed, max_concurrency)

      running =
        Enum.reduce(seed, %{}, fn {elem, idx, attempts}, acc ->
          {ref, entry} = start_attempt(self(), func, elem, idx, attempts, timeout)
          Map.put(acc, ref, entry)
        end)

      results = loop(running, queue, cfg, %{})
      Enum.map(0..(total - 1), &Map.fetch!(results, &1))
    end
  end

  # Spawns one attempt for `elem`, arms a per-attempt timeout, and returns the
  # bookkeeping entry keyed by a fresh ref.
  defp start_attempt(parent, func, elem, idx, attempts_left, timeout) do
    ref = make_ref()

    {pid, mon} =
      spawn_monitor(fn ->
        result =
          try do
            {:ok, func.(elem)}
          rescue
            e -> {:error, {:exception, e}}
          catch
            :exit, r -> {:error, {:exit, r}}
            :throw, t -> {:error, {:throw, t}}
          end

        send(parent, {ref, result})
      end)

    timer = Process.send_after(parent, {:timeout, ref}, timeout)
    {ref, {pid, mon, idx, elem, attempts_left, timer}}
  end

  # TODO: implement loop/4

  defp fill(running, [], _cfg), do: {running, []}

  defp fill(running, [{elem, idx, attempts} | rest], cfg) do
    {ref, entry} = start_attempt(self(), cfg.func, elem, idx, attempts, cfg.timeout)
    {Map.put(running, ref, entry), rest}
  end

  defp cleanup(mon, timer) do
    Process.demonitor(mon, [:flush])
    Process.cancel_timer(timer)
    :ok
  end

  defp drain(ref) do
    receive do
      {^ref, _} -> :ok
    after
      0 -> :ok
    end
  end
end
```