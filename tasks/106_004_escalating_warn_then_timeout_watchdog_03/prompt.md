# Escalating (Warn-then-Timeout) Watchdog Timer GenServer

Below is a nearly complete `EscalatingWatchdog` GenServer. Your job is to implement
the private `cancel_entry/2` helper — every other function is already written.

## Implement `cancel_entry/2`

`cancel_entry(state, name)` is a private helper that fully removes a registration from
the watchdog state, making sure its pending timers can never fire again. It takes the
current `state` map (keyed by `name`) and the `name` to remove, and returns the updated
state map.

It should:

- Look up `name` in `state`.
- If an entry exists, cancel that entry's armed timers by calling `disarm/1` on it (so
  the stale `:warn`/`:timeout` messages are cancelled), then remove `name` from the map
  and return the resulting state.
- If no entry exists for `name`, return `state` unchanged (removing an unknown `name` is
  a harmless no-op).

This helper is used both when a registration is replaced (`{:register, ...}`) and when a
name is unregistered (`{:unregister, name}`).

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
  def handle_call({:register, name, pid, warn_ms, timeout_ms, warn_fn, timeout_fn}, _from, state) do
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
    # TODO
  end

  defp safe_invoke(fun, name) do
    fun.(name)
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end
end
```