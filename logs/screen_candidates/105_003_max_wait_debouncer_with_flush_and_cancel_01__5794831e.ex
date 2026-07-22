defmodule MaxWaitDebouncer do
  @moduledoc """
  A per-key debouncer with a guaranteed maximum wait, plus manual flush and cancel.

  A plain debouncer can starve indefinitely: while calls keep arriving faster than
  `delay_ms`, the timer keeps resetting and the function never runs. `MaxWaitDebouncer`
  bounds that starvation. Each burst records when its *first* call happened, and the
  pending function is guaranteed to fire no later than `first_call_at + max_ms`.

  This mirrors the `maxWait` option of lodash's `debounce`.

  ## Semantics

    * **Coalescing** — calling `call/4` again with the same key before the key's timer
      fires replaces the pending function and reschedules the timer. Only one function
      runs per burst.
    * **Max wait** — each call schedules the next fire at
      `min(delay_ms, remaining_until_max)` where
      `remaining_until_max = first_call_at + max_ms - now`, clamped at zero. The function
      that eventually runs is the most recently supplied one.
    * **State cleared after firing** — after a fire (by delay, by max wait, or by
      `flush/1`) the key's state is dropped, so the next `call/4` begins a fresh burst
      with a new max-wait window.
    * **Keys are independent** — every key has its own timer, burst start time and
      pending function.

  Functions are executed in a spawned process, so a slow or crashing function cannot
  wedge the server.

  ## Example

      {:ok, _pid} = MaxWaitDebouncer.start_link([])

      # Autosave at most 2s after the last keystroke, but never later than 10s
      # after the first keystroke of the burst.
      MaxWaitDebouncer.call(:autosave, 2_000, 10_000, fn -> save_document() end)

      # Save right now, if anything is pending.
      MaxWaitDebouncer.flush(:autosave)

      # Throw away the pending save.
      MaxWaitDebouncer.cancel(:autosave)
  """

  use GenServer

  @type key :: term()
  @type func :: (-> any())

  defmodule Entry do
    @moduledoc false

    @enforce_keys [:timer, :first_call_at, :max_ms, :func]
    defstruct [:timer, :first_call_at, :max_ms, :func]
  end

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc """
  Starts the debouncer process.

  Accepts a `:name` option used for process registration; it defaults to
  `#{inspect(__MODULE__)}`. Any other options are passed through to `GenServer.start_link/3`.

  Returns `{:ok, pid}`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, :ok, [{:name, name} | opts])
  end

  @doc """
  Schedules the zero-arity `func` to run for `key`.

  The function fires `delay_ms` after the most recent call for `key`, but no later than
  `max_ms` after the first call of the current burst. Repeated calls within the burst
  replace the pending function and reschedule the timer.

  `max_ms` must be greater than or equal to `delay_ms`. Returns `:ok` immediately; the
  function never runs on the caller's process.
  """
  @spec call(key(), non_neg_integer(), non_neg_integer(), func()) :: :ok
  def call(key, delay_ms, max_ms, func)
      when is_integer(delay_ms) and delay_ms >= 0 and
             is_integer(max_ms) and max_ms >= delay_ms and
             is_function(func, 0) do
    GenServer.cast(__MODULE__, {:call, key, delay_ms, max_ms, func})
  end

  @doc """
  Runs the pending function for `key` immediately, if there is one, and clears the key's
  state (including its timer).

  Returns `:ok`, whether or not anything was pending.
  """
  @spec flush(key()) :: :ok
  def flush(key) do
    GenServer.call(__MODULE__, {:flush, key})
  end

  @doc """
  Discards the pending function for `key` without running it, cancelling its timer.

  Returns `:ok`, whether or not anything was pending.
  """
  @spec cancel(key()) :: :ok
  def cancel(key) do
    GenServer.call(__MODULE__, {:cancel, key})
  end

  # ── GenServer callbacks ─────────────────────────────────────────────────────

  @impl true
  def init(:ok) do
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:call, key, delay_ms, max_ms, func}, entries) do
    now = now_ms()

    {first_call_at, max_ms} =
      case Map.fetch(entries, key) do
        {:ok, %Entry{timer: timer, first_call_at: first_call_at, max_ms: existing_max}} ->
          cancel_timer(timer)
          {first_call_at, existing_max}

        :error ->
          {now, max_ms}
      end

    wait = next_wait(first_call_at, max_ms, delay_ms, now)
    timer = Process.send_after(self(), {:fire, key}, wait)

    entry = %Entry{timer: timer, first_call_at: first_call_at, max_ms: max_ms, func: func}
    {:noreply, Map.put(entries, key, entry)}
  end

  @impl true
  def handle_call({:flush, key}, _from, entries) do
    case Map.pop(entries, key) do
      {%Entry{timer: timer, func: func}, entries} ->
        cancel_timer(timer)
        run(func)
        {:reply, :ok, entries}

      {nil, entries} ->
        {:reply, :ok, entries}
    end
  end

  @impl true
  def handle_call({:cancel, key}, _from, entries) do
    case Map.pop(entries, key) do
      {%Entry{timer: timer}, entries} ->
        cancel_timer(timer)
        {:reply, :ok, entries}

      {nil, entries} ->
        {:reply, :ok, entries}
    end
  end

  @impl true
  def handle_info({:fire, key}, entries) do
    case Map.pop(entries, key) do
      {%Entry{func: func}, entries} ->
        run(func)
        {:noreply, entries}

      {nil, entries} ->
        {:noreply, entries}
    end
  end

  @impl true
  def handle_info(_msg, entries) do
    {:noreply, entries}
  end

  # ── Internals ───────────────────────────────────────────────────────────────

  # The next fire happens at `min(delay_ms, remaining_until_max)`, never negative.
  @spec next_wait(integer(), non_neg_integer(), non_neg_integer(), integer()) ::
          non_neg_integer()
  defp next_wait(first_call_at, max_ms, delay_ms, now) do
    remaining_until_max = max(first_call_at + max_ms - now, 0)
    min(delay_ms, remaining_until_max)
  end

  @spec run(func()) :: :ok
  defp run(func) do
    _pid = spawn(func)
    :ok
  end

  @spec cancel_timer(reference()) :: :ok
  defp cancel_timer(timer) do
    Process.cancel_timer(timer)

    receive do
      {:fire, _key} -> :ok
    after
      0 -> :ok
    end

    :ok
  end

  @spec now_ms() :: integer()
  defp now_ms do
    System.monotonic_time(:millisecond)
  end
end