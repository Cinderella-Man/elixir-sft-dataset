# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule EdgeDebouncer do
  use GenServer

  @valid_edges [:trailing, :leading, :both]

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  def call(key, delay_ms, func, opts \\ [])
      when is_integer(delay_ms) and delay_ms >= 0 and is_function(func, 0) and is_list(opts) do
    edge = Keyword.get(opts, :edge, :trailing)

    unless edge in @valid_edges do
      raise ArgumentError,
            "invalid :edge #{inspect(edge)}, expected one of #{inspect(@valid_edges)}"
    end

    GenServer.cast(__MODULE__, {:debounce, key, delay_ms, func, edge})
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_cast({:debounce, key, delay_ms, func, edge}, state) do
    case Map.get(state, key) do
      nil ->
        # First call of a new burst: leading edges fire immediately.
        if edge in [:leading, :both], do: run(func)
        entry = Map.merge(arm(key, delay_ms), %{edge: edge, calls: 1, last_func: func})
        {:noreply, Map.put(state, key, entry)}

      %{timer: ref} = entry ->
        # cancel_timer/1 can return false with the old {:fire, …} already
        # sitting in the mailbox — the fresh token below makes that stale
        # message a no-op instead of an early trailing fire.
        Process.cancel_timer(ref)
        entry = %{entry | calls: entry.calls + 1, last_func: func}
        entry = Map.merge(entry, arm(key, delay_ms))
        {:noreply, Map.put(state, key, entry)}
    end
  end

  @impl true
  def handle_info({:fire, key, token}, state) do
    case Map.get(state, key) do
      # Only the CURRENT burst's token may fire; a stale timer message from a
      # superseded burst (its cancel arrived too late) is discarded.
      %{token: ^token} = entry ->
        cond do
          entry.edge == :trailing -> run(entry.last_func)
          entry.edge == :both and entry.calls > 1 -> run(entry.last_func)
          true -> :ok
        end

        {:noreply, Map.delete(state, key)}

      _ ->
        {:noreply, state}
    end
  end

  # Arm the burst's timer under a fresh token; {:fire, key, token} only acts
  # while the entry still carries this exact token.
  defp arm(key, delay_ms) do
    token = make_ref()
    %{timer: Process.send_after(self(), {:fire, key, token}, delay_ms), token: token}
  end

  # Run the func off the server's reduction path.
  defp run(func), do: spawn(fn -> func.() end)
end
```
