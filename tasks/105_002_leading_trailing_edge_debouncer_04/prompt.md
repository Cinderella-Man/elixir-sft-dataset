# Fill in the middle — `EdgeDebouncer.call/4`

Implement the public `call/4` function. It is the sole entry point clients use to
schedule a debounced, zero-arity `func` for a given `key`.

The function head is already given, including its `@spec`, the `opts \\ []`
default, and the guard (`delay_ms` is a non-negative integer, `func` is a
zero-arity function, and `opts` is a list). Your body must:

1. Read the firing edge from `opts` under the `:edge` key, defaulting to
   `:trailing` when not supplied.
2. Validate the edge against the module's `@valid_edges` (`:trailing`,
   `:leading`, `:both`). If it is not one of those, raise `ArgumentError` with a
   message that reports the offending value and the accepted values (use
   `inspect/1` for both).
3. Otherwise, hand the work to the server without blocking: cast
   `{:debounce, key, delay_ms, func, edge}` to the process registered under the
   module name (`__MODULE__`). The `GenServer.cast/2` call yields `:ok`, which is
   exactly what `call/4` must return — it must never wait for `func` to run.

Here is the whole module, with only the body of `call/4` replaced by `# TODO`:

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
  @spec start_link(keyword()) :: GenServer.on_start()
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
    # TODO
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