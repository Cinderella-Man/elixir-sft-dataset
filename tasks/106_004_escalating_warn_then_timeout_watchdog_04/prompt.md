Implement the private `safe_invoke/2` function. It takes a one-argument callback
function `fun` and a `name`, and invokes the callback as `fun.(name)`. The invocation
must be defensive: if the callback raises an exception, it should be rescued and the
function should return `:ok` instead of propagating the error; likewise, if the callback
throws or exits, it should be caught and `:ok` returned. This ensures a misbehaving
warn/timeout callback can never crash the watchdog GenServer.

```elixir
defmodule EscalatingWatchdog do
  @moduledoc """
  A GenServer that monitors liveness via heartbeats with two escalation stages.

  Each registration has an early `warn_ms` deadline and a later `timeout_ms`
  deadline (measured from the last heartbeat or from registration). With no
  heartbeat, `on_warn_fn.(name)` fires once at `warn_ms` (moving the phase to
  `:warned`), and `on_timeout_fn.(name)` fires once at `timeout_ms`, after which the
  registration is removed. A heartbeat resets both deadlines and returns the phase to
  `:healthy`, so a heartbeat after a warning re-arms a fresh warn/timeout pair.

  Each generation of timers is tagged with a unique reference so stale timers (from a
  reset or an unregister) can never fire spuriously.
  """

  use GenServer

  ## Public API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Registers an escalating watchdog for `name`/`pid`: runs `on_warn_fn` after `warn_ms`
  of silence, then `on_timeout_fn` after `timeout_ms`. Returns `:ok`.
  """
  @spec register(
          term(),
          pid(),
          non_neg_integer(),
          non_neg_integer(),
          (term() -> any()),
          (term() -> any())
        ) :: :ok
  def register(name, pid, warn_ms, timeout_ms, on_warn_fn, on_timeout_fn)
      when is_integer(warn_ms) and warn_ms >= 0 and is_integer(timeout_ms) and
             is_function(on_warn_fn, 1) and is_function(on_timeout_fn, 1) do
    unless warn_ms < timeout_ms do
      raise ArgumentError, "warn_ms must be strictly less than timeout_ms"
    end

    GenServer.call(
      __MODULE__,
      {:register, name, pid, warn_ms, timeout_ms, on_warn_fn, on_timeout_fn}
    )
  end

  @spec heartbeat(term()) :: :ok
  def heartbeat(name), do: GenServer.call(__MODULE__, {:heartbeat, name})

  @spec unregister(term()) :: :ok
  def unregister(name), do: GenServer.call(__MODULE__, {:unregister, name})

  @spec phase(term()) :: {:ok, :healthy | :warned} | {:error, :not_registered}
  def phase(name), do: GenServer.call(__MODULE__, {:phase, name})

  ## GenServer callbacks

  @impl true
  def init(_arg), do: {:ok, %{}}

  @impl true
  def handle_call(
        {:register, name, pid, warn_ms, timeout_ms, warn_fn, timeout_fn},
        _from,
        state
      ) do
    state = cancel_entry(state, name)

    entry =
      arm(
        %{
          pid: pid,
          warn_ms: warn_ms,
          timeout_ms: timeout_ms,
          warn_fn: warn_fn,
          timeout_fn: timeout_fn
        },
        name
      )

    {:reply, :ok, Map.put(state, name, entry)}
  end

  def handle_call({:heartbeat, name}, _from, state) do
    case Map.fetch(state, name) do
      {:ok, entry} ->
        entry = entry |> disarm() |> arm(name)
        {:reply, :ok, Map.put(state, name, entry)}

      :error ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:unregister, name}, _from, state) do
    {:reply, :ok, cancel_entry(state, name)}
  end

  def handle_call({:phase, name}, _from, state) do
    case Map.fetch(state, name) do
      {:ok, entry} -> {:reply, {:ok, entry.phase}, state}
      :error -> {:reply, {:error, :not_registered}, state}
    end
  end

  @impl true
  def handle_info({:warn, name, ref}, state) do
    case Map.fetch(state, name) do
      {:ok, %{ref: ^ref, phase: :healthy} = entry} ->
        safe_invoke(entry.warn_fn, name)
        {:noreply, Map.put(state, name, %{entry | phase: :warned})}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:timeout, name, ref}, state) do
    case Map.fetch(state, name) do
      {:ok, %{ref: ^ref} = entry} ->
        safe_invoke(entry.timeout_fn, name)
        {:noreply, Map.delete(state, name)}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  ## Helpers

  defp arm(entry, name) do
    ref = make_ref()
    warn_timer = Process.send_after(self(), {:warn, name, ref}, entry.warn_ms)
    timeout_timer = Process.send_after(self(), {:timeout, name, ref}, entry.timeout_ms)

    Map.merge(entry, %{
      ref: ref,
      phase: :healthy,
      warn_timer: warn_timer,
      timeout_timer: timeout_timer
    })
  end

  defp disarm(entry) do
    _ = Process.cancel_timer(entry.warn_timer)
    _ = Process.cancel_timer(entry.timeout_timer)
    entry
  end

  defp cancel_entry(state, name) do
    case Map.fetch(state, name) do
      {:ok, entry} ->
        disarm(entry)
        Map.delete(state, name)

      :error ->
        state
    end
  end

  defp safe_invoke(fun, name) do
    # TODO
  end
end

```