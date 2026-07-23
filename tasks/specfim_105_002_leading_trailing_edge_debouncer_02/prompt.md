# Fill in one @spec

Below: a working module where the `@spec` for
`start_link/1` has been removed (see the `# TODO: @spec` marker).
Provide exactly that typespec, consistent with the implementation's
arguments, guards, and all reachable return shapes. No other edits.

## The module with the `@spec` for `start_link/1` missing

```elixir
defmodule EdgeDebouncer do
  @moduledoc """
  A `GenServer` that debounces zero-arity function calls on a per-key basis with
  a configurable firing edge: `:trailing` (default), `:leading`, or `:both`.

  A *burst* for a key begins with a `call/4` when the key has no pending timer
  and ends after `delay_ms` of quiet. The edge chosen by the first call of the
  burst decides when the function(s) run:

    * `:trailing` — only the most recent func runs, once, after the burst settles.
    * `:leading`  — the first func runs immediately; nothing runs at the end.
    * `:both`     — the first func runs immediately, and if any further calls
      arrived the most recent func also runs once at the end (a lone call fires
      leading only, never twice).
  """

  use GenServer

  @valid_edges [:trailing, :leading, :both]

  @doc """
  Starts the debouncer. Accepts a `:name` option for registration, defaulting to
  `EdgeDebouncer`.
  """
  # TODO: @spec
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Handles a debounced `func` for `key`. `opts` may include `:edge`
  (`:trailing` | `:leading` | `:both`, default `:trailing`). Returns `:ok`
  promptly. Raises `ArgumentError` for an invalid edge.
  """
  @spec call(term(), non_neg_integer(), (-> any()), keyword()) :: :ok
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

The `@spec` attribute only — nothing more.
