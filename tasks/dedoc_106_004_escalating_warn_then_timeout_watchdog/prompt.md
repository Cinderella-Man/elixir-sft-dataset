# Add moduledoc, docs, and specs

Below: a correct, tested, undocumented module. Deliver the same module
fully documented — a `@moduledoc`, a per-public-function `@doc` and
`@spec`, and supporting `@type`s where useful. Behavior, names, structure:
unchanged. One file.

## The module

```elixir
defmodule EscalatingWatchdog do
  use GenServer

  ## Public API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

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

  def heartbeat(name), do: GenServer.call(__MODULE__, {:heartbeat, name})

  def unregister(name), do: GenServer.call(__MODULE__, {:unregister, name})

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
    fun.(name)
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end
end
```
