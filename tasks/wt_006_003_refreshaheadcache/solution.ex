defmodule RefreshAheadCache do
  @moduledoc """
  A GenServer-based TTL cache that proactively refreshes entries approaching
  expiration by running a user-supplied loader function in a background task.

  Each entry stores `{value, expires_at, ttl_ms, loader}`.  A `get/2` that
  observes `age >= refresh_threshold * ttl_ms` schedules a refresh (if none is
  already in flight for that key) and returns the current value.  When the
  refresh completes, its result replaces the entry with a fresh TTL.

  In-flight refreshes are tracked by a `make_ref()` token per key.  Results
  from background tasks are matched against the currently-tracked token; if
  the token has changed (due to `put/5`, `delete/2`, or a newer refresh),
  the result is discarded.

  ## Options

    * `:name`                – optional process registration
    * `:clock`               – `(-> integer())` current time in ms
    * `:sweep_interval_ms`   – hard-expiry sweep interval (default 60_000)
    * `:refresh_threshold`   – float in (0.0, 1.0] (default 0.8)

  """

  use GenServer

  defstruct [
    :clock,
    :sweep_interval_ms,
    :refresh_threshold,
    entries: %{},
    in_flight: %{}
  ]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    refresh_threshold = Keyword.get(opts, :refresh_threshold, 0.8)

    unless is_number(refresh_threshold) and refresh_threshold > 0.0 and refresh_threshold <= 1.0 do
      raise ArgumentError,
            ":refresh_threshold must be a number in (0.0, 1.0], got: #{inspect(refresh_threshold)}"
    end

    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @spec put(GenServer.server(), term(), term(), pos_integer(), (-> term())) :: :ok
  def put(server, key, value, ttl_ms, loader)
      when is_integer(ttl_ms) and ttl_ms > 0 and is_function(loader, 0) do
    GenServer.call(server, {:put, key, value, ttl_ms, loader})
  end

  @spec get(GenServer.server(), term()) :: {:ok, term()} | :miss
  def get(server, key), do: GenServer.call(server, {:get, key})

  @spec delete(GenServer.server(), term()) :: :ok
  def delete(server, key), do: GenServer.call(server, {:delete, key})

  @spec stats(GenServer.server()) :: %{entries: non_neg_integer(), refreshes_in_flight: non_neg_integer()}
  def stats(server), do: GenServer.call(server, :stats)

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    sweep_interval_ms = Keyword.get(opts, :sweep_interval_ms, 60_000)
    refresh_threshold = Keyword.get(opts, :refresh_threshold, 0.8)

    schedule_sweep(sweep_interval_ms)

    {:ok,
     %__MODULE__{
       clock: clock,
       sweep_interval_ms: sweep_interval_ms,
       refresh_threshold: refresh_threshold * 1.0
     }}
  end

  @impl true
  def handle_call({:put, key, value, ttl_ms, loader}, _from, state) do
    now = state.clock.()

    entry = %{
      value: value,
      expires_at: now + ttl_ms,
      ttl_ms: ttl_ms,
      loader: loader
    }

    # Invalidate any in-flight refresh for this key so a stale result can't
    # clobber the new put.
    new_in_flight = Map.delete(state.in_flight, key)

    {:reply, :ok,
     %{state | entries: Map.put(state.entries, key, entry), in_flight: new_in_flight}}
  end

  def handle_call({:get, key}, _from, state) do
    now = state.clock.()

    case Map.fetch(state.entries, key) do
      {:ok, entry} ->
        cond do
          # Hard expiry — evict lazily and miss.
          now >= entry.expires_at ->
            new_in_flight = Map.delete(state.in_flight, key)

            {:reply, :miss,
             %{
               state
               | entries: Map.delete(state.entries, key),
                 in_flight: new_in_flight
             }}

          # Past refresh threshold — trigger an async refresh if none running.
          should_refresh?(entry, now, state.refresh_threshold) and
              not Map.has_key?(state.in_flight, key) ->
            task_ref = spawn_refresh(key, entry.loader)
            new_in_flight = Map.put(state.in_flight, key, task_ref)
            {:reply, {:ok, entry.value}, %{state | in_flight: new_in_flight}}

          # Fresh enough OR refresh already in flight — just return value.
          true ->
            {:reply, {:ok, entry.value}, state}
        end

      :error ->
        {:reply, :miss, state}
    end
  end

  def handle_call({:delete, key}, _from, state) do
    {:reply, :ok,
     %{
       state
       | entries: Map.delete(state.entries, key),
         in_flight: Map.delete(state.in_flight, key)
     }}
  end

  def handle_call(:stats, _from, state) do
    {:reply,
     %{
       entries: map_size(state.entries),
       refreshes_in_flight: map_size(state.in_flight)
     }, state}
  end

  # Refresh result: apply only if entry still exists AND task_ref still matches.
  @impl true
  def handle_info({:refresh_complete, key, task_ref, new_value}, state) do
    case {Map.fetch(state.entries, key), Map.fetch(state.in_flight, key)} do
      {{:ok, entry}, {:ok, ^task_ref}} ->
        now = state.clock.()
        updated = %{entry | value: new_value, expires_at: now + entry.ttl_ms}

        {:noreply,
         %{
           state
           | entries: Map.put(state.entries, key, updated),
             in_flight: Map.delete(state.in_flight, key)
         }}

      _ ->
        # Key gone, overwritten, or a newer refresh is in flight — discard.
        new_in_flight =
          case Map.fetch(state.in_flight, key) do
            {:ok, ^task_ref} -> Map.delete(state.in_flight, key)
            _ -> state.in_flight
          end

        {:noreply, %{state | in_flight: new_in_flight}}
    end
  end

  def handle_info({:refresh_failed, key, task_ref, _reason}, state) do
    # Leave the old value in place; just clear the in-flight marker if still ours.
    new_in_flight =
      case Map.fetch(state.in_flight, key) do
        {:ok, ^task_ref} -> Map.delete(state.in_flight, key)
        _ -> state.in_flight
      end

    {:noreply, %{state | in_flight: new_in_flight}}
  end

  def handle_info(:sweep, state) do
    now = state.clock.()

    pruned =
      state.entries
      |> Enum.reject(fn {_k, %{expires_at: e}} -> now >= e end)
      |> Map.new()

    new_in_flight =
      state.in_flight
      |> Enum.filter(fn {k, _ref} -> Map.has_key?(pruned, k) end)
      |> Map.new()

    schedule_sweep(state.sweep_interval_ms)

    {:noreply, %{state | entries: pruned, in_flight: new_in_flight}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Refresh machinery — runs outside the GenServer
  # ---------------------------------------------------------------------------

  defp spawn_refresh(key, loader) do
    task_ref = make_ref()
    parent = self()

    _ =
      Task.start_link(fn ->
        try do
          new_value = loader.()
          send(parent, {:refresh_complete, key, task_ref, new_value})
        rescue
          e -> send(parent, {:refresh_failed, key, task_ref, e})
        catch
          kind, reason -> send(parent, {:refresh_failed, key, task_ref, {kind, reason}})
        end
      end)

    task_ref
  end

  defp should_refresh?(entry, now, threshold) do
    age = now - (entry.expires_at - entry.ttl_ms)
    age >= threshold * entry.ttl_ms
  end

  defp schedule_sweep(:infinity), do: :ok
  defp schedule_sweep(ms) when is_integer(ms) and ms > 0 do
    Process.send_after(self(), :sweep, ms)
  end
end
