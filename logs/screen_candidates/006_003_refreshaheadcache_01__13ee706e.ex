defmodule RefreshAheadCache do
  @moduledoc """
  A TTL cache that **proactively refreshes** entries approaching expiration.

  A plain TTL cache has a latency "cliff" at expiration: the first read after a
  key expires must recompute the value while the caller waits, causing latency
  spikes and thundering-herd problems.

  `RefreshAheadCache` avoids this by storing a zero-arity **loader** alongside
  each value. When a read observes that an entry has crossed a configurable
  fraction of its TTL (the `:refresh_threshold`, default `0.8`), a background
  task is spawned to re-run the loader. Reads during the refresh window keep
  returning the current (still-fresh) value; when the loader completes, the new
  value atomically replaces the old one and the TTL clock restarts using the
  entry's *original* configured TTL.

  ## Concurrency and correctness

  Refreshes are tracked in an in-flight map (`%{key => task_ref}`) so that:

    * concurrent reads do not trigger duplicate refreshes for the same key;
    * a refresh result is applied only if the key still exists and its
      `task_ref` still matches — otherwise the result is discarded (the key was
      deleted, overwritten by `put/5`, or superseded by a newer refresh).

  The loader runs in the spawned task, never inside the GenServer, so the server
  is never blocked on I/O.
  """

  use GenServer

  @type key :: term()
  @type value :: term()
  @type loader :: (-> value())
  @type clock :: (-> integer())

  defmodule Entry do
    @moduledoc false
    defstruct [:value, :expires_at, :ttl_ms, :loader]
  end

  @default_sweep_interval_ms 60_000
  @default_refresh_threshold 0.8

  ## Public API

  @doc """
  Starts the cache process.

  ## Options

    * `:name` — optional process registration name.
    * `:clock` — zero-arity function returning current time in ms
      (default `fn -> System.monotonic_time(:millisecond) end`).
    * `:sweep_interval_ms` — periodic hard-expiry sweep interval in ms
      (default `#{@default_sweep_interval_ms}`); `:infinity` disables it.
    * `:refresh_threshold` — float in `(0.0, 1.0]`, the fraction of the TTL
      after which a refresh is triggered (default `#{@default_refresh_threshold}`).

  Raises `ArgumentError` in the calling process if `:refresh_threshold` is not a
  number in `(0.0, 1.0]`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    threshold = Keyword.get(opts, :refresh_threshold, @default_refresh_threshold)
    validate_threshold!(threshold)

    gen_opts =
      case Keyword.get(opts, :name) do
        nil -> []
        name -> [name: name]
      end

    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Stores `key` with an initial `value`, a TTL in milliseconds, and a zero-arity
  `loader` used to recompute the value on refresh.

  If the key already exists, its value, TTL and loader are overwritten, and any
  refresh currently in flight for the key is disowned (its eventual result will
  be discarded). Always returns `:ok`.
  """
  @spec put(GenServer.server(), key(), value(), pos_integer(), loader()) :: :ok
  def put(server, key, value, ttl_ms, loader)
      when is_integer(ttl_ms) and ttl_ms > 0 and is_function(loader, 0) do
    GenServer.call(server, {:put, key, value, ttl_ms, loader})
  end

  @doc """
  Retrieves `key`.

  Returns `:miss` if the key is absent or past hard expiry (the expired entry is
  deleted on read). Otherwise returns `{:ok, value}`; if the entry has crossed
  the refresh threshold and no refresh is already in flight, one is triggered
  asynchronously while the current value is returned.
  """
  @spec get(GenServer.server(), key()) :: {:ok, value()} | :miss
  def get(server, key) do
    GenServer.call(server, {:get, key})
  end

  @doc """
  Removes `key`. If a refresh is in flight for the key, its eventual result is
  discarded. Always returns `:ok`.
  """
  @spec delete(GenServer.server(), key()) :: :ok
  def delete(server, key) do
    GenServer.call(server, {:delete, key})
  end

  @doc """
  Returns cache statistics: the number of stored `:entries` and the number of
  `:refreshes_in_flight`.
  """
  @spec stats(GenServer.server()) :: %{
          entries: non_neg_integer(),
          refreshes_in_flight: non_neg_integer()
        }
  def stats(server) do
    GenServer.call(server, :stats)
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    sweep_interval_ms = Keyword.get(opts, :sweep_interval_ms, @default_sweep_interval_ms)
    threshold = Keyword.get(opts, :refresh_threshold, @default_refresh_threshold)

    state = %{
      entries: %{},
      in_flight: %{},
      clock: clock,
      sweep_interval_ms: sweep_interval_ms,
      refresh_threshold: threshold
    }

    schedule_sweep(sweep_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_call({:put, key, value, ttl_ms, loader}, _from, state) do
    now = state.clock.()

    entry = %Entry{
      value: value,
      expires_at: now + ttl_ms,
      ttl_ms: ttl_ms,
      loader: loader
    }

    state =
      state
      |> put_in([:entries, key], entry)
      |> update_in([:in_flight], &Map.delete(&1, key))

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    now = state.clock.()

    case Map.get(state.entries, key) do
      nil ->
        {:reply, :miss, state}

      %Entry{expires_at: expires_at} when now >= expires_at ->
        state = update_in(state.entries, &Map.delete(&1, key))
        {:reply, :miss, state}

      %Entry{} = entry ->
        state = maybe_trigger_refresh(state, key, entry, now)
        {:reply, {:ok, entry.value}, state}
    end
  end

  @impl true
  def handle_call({:delete, key}, _from, state) do
    state =
      state
      |> update_in([:entries], &Map.delete(&1, key))
      |> update_in([:in_flight], &Map.delete(&1, key))

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      entries: map_size(state.entries),
      refreshes_in_flight: map_size(state.in_flight)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:sweep, state) do
    state = sweep(state)
    schedule_sweep(state.sweep_interval_ms)
    {:noreply, state}
  end

  @impl true
  def handle_info({:refresh_complete, key, task_ref, new_value}, state) do
    state =
      if refresh_current?(state, key, task_ref) do
        now = state.clock.()
        entry = Map.fetch!(state.entries, key)
        updated = %Entry{entry | value: new_value, expires_at: now + entry.ttl_ms}

        state
        |> put_in([:entries, key], updated)
        |> update_in([:in_flight], &Map.delete(&1, key))
      else
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({:refresh_failed, key, task_ref, _reason}, state) do
    state =
      if refresh_current?(state, key, task_ref) do
        update_in(state.in_flight, &Map.delete(&1, key))
      else
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Internal helpers

  @spec validate_threshold!(term()) :: :ok
  defp validate_threshold!(threshold)
       when is_number(threshold) and threshold > 0 and threshold <= 1 do
    :ok
  end

  defp validate_threshold!(threshold) do
    raise ArgumentError,
          ":refresh_threshold must be a number in (0.0, 1.0], got: #{inspect(threshold)}"
  end

  @spec maybe_trigger_refresh(map(), key(), Entry.t(), integer()) :: map()
  defp maybe_trigger_refresh(state, key, entry, now) do
    cond do
      Map.has_key?(state.in_flight, key) ->
        state

      past_threshold?(entry, now, state.refresh_threshold) ->
        start_refresh(state, key, entry)

      true ->
        state
    end
  end

  @spec past_threshold?(Entry.t(), integer(), float()) :: boolean()
  defp past_threshold?(%Entry{expires_at: expires_at, ttl_ms: ttl_ms}, now, threshold) do
    age = now - (expires_at - ttl_ms)
    age >= threshold * ttl_ms
  end

  @spec start_refresh(map(), key(), Entry.t()) :: map()
  defp start_refresh(state, key, %Entry{loader: loader}) do
    task_ref = make_ref()
    server = self()

    {:ok, _pid} =
      Task.start_link(fn ->
        try do
          new_value = loader.()
          send(server, {:refresh_complete, key, task_ref, new_value})
        catch
          kind, reason ->
            send(server, {:refresh_failed, key, task_ref, {kind, reason}})
        end
      end)

    put_in(state, [:in_flight, key], task_ref)
  end

  @spec refresh_current?(map(), key(), reference()) :: boolean()
  defp refresh_current?(state, key, task_ref) do
    Map.has_key?(state.entries, key) and Map.get(state.in_flight, key) == task_ref
  end

  @spec sweep(map()) :: map()
  defp sweep(state) do
    now = state.clock.()

    entries =
      state.entries
      |> Enum.reject(fn {_key, %Entry{expires_at: expires_at}} -> expires_at <= now end)
      |> Map.new()

    %{state | entries: entries}
  end

  @spec schedule_sweep(non_neg_integer() | :infinity) :: :ok
  defp schedule_sweep(:infinity), do: :ok

  defp schedule_sweep(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :sweep, interval_ms)
    :ok
  end
end