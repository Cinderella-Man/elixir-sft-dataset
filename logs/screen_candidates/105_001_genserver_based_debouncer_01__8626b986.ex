defmodule Debouncer do
  @moduledoc """
  A `GenServer` that debounces zero-arity functions on a per-key basis.

  Each call to `call/3` schedules a function to run after a delay. If another
  call arrives for the same key before the pending timer fires, the timer is
  restarted with the new delay and the new function replaces the pending one.
  When a burst of calls for a key finally settles, only the most recently
  supplied function for that key runs, exactly once.

  Timers are tagged with a unique reference so that a stale expiry message —
  one that was already delivered to the server's mailbox before its timer could
  be cancelled — is recognized and discarded instead of firing early.

  Functions are executed in a spawned process, so a slow, crashing, or exiting
  function cannot wedge the server, delay other keys, or block subsequent calls.
  """

  use GenServer

  @typedoc "Any term used to identify an independent debounce slot."
  @type key :: term()

  @typedoc "Internal server state: a map of key to `{timer_ref, unique_ref, func}`."
  @opaque state :: %{key() => {reference(), reference(), (-> any())}}

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc """
  Starts the debouncer.

  Accepts a `:name` option used for process registration, defaulting to
  `#{inspect(__MODULE__)}`. Returns `{:ok, pid}`, or
  `{:error, {:already_started, pid}}` if a process is already registered under
  that name. The server starts with no pending keys.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, :ok, name: name)
  end

  @doc """
  Schedules `func` to run after `delay_ms` milliseconds, debounced on `key`.

  Returns `:ok` immediately; it never blocks on the server or on `func`. A
  subsequent call with the same key before the timer fires resets the timer and
  replaces the pending function. A `delay_ms` of `0` still runs `func`
  asynchronously rather than inline in the caller.

  Raises `FunctionClauseError` unless `delay_ms` is a non-negative integer and
  `func` is a zero-arity function.
  """
  @spec call(key(), non_neg_integer(), (-> any())) :: :ok
  def call(key, delay_ms, func)
      when is_integer(delay_ms) and delay_ms >= 0 and is_function(func, 0) do
    GenServer.cast(__MODULE__, {:debounce, key, delay_ms, func})
  end

  # ── GenServer callbacks ─────────────────────────────────────────────────────

  @impl GenServer
  @spec init(:ok) :: {:ok, state()}
  def init(:ok), do: {:ok, %{}}

  @impl GenServer
  def handle_cast({:debounce, key, delay_ms, func}, state) do
    case Map.fetch(state, key) do
      {:ok, {timer_ref, _unique_ref, _old_func}} -> Process.cancel_timer(timer_ref)
      :error -> :ok
    end

    unique_ref = make_ref()
    timer_ref = Process.send_after(self(), {:expired, key, unique_ref}, delay_ms)
    {:noreply, Map.put(state, key, {timer_ref, unique_ref, func})}
  end

  @impl GenServer
  def handle_info({:expired, key, unique_ref}, state) do
    case Map.fetch(state, key) do
      {:ok, {_timer_ref, ^unique_ref, func}} ->
        spawn(fn -> func.() end)
        {:noreply, Map.delete(state, key)}

      _stale_or_missing ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}
end