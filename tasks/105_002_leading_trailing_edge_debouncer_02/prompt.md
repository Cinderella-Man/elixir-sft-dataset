# Implement `handle_cast/2` for `EdgeDebouncer`

Implement the `handle_cast/2` clause that handles the `{:debounce, key, delay_ms,
func, edge}` message cast by `call/4`. It drives the debounce state machine for a
single `key`.

Look up `key` in `state`:

- **No existing entry (`nil`) — this call opens a new burst.** If `edge` is
  `:leading` or `:both`, run `func` immediately via `run/1` (the leading edge
  fires right away). Schedule the trailing timer with `Process.send_after/3`,
  sending `{:fire, key}` to `self()` after `delay_ms`. Store a fresh entry for the
  key holding the timer reference, the `edge`, a call count of `1`, and `func` as
  the most-recent (`last_func`).

- **An existing entry — this call arrives mid-burst.** Cancel the pending timer
  with `Process.cancel_timer/1`, then schedule a replacement `{:fire, key}` timer
  for `delay_ms` (restarting the delay). Update the entry in place: swap in the
  new timer reference, increment the call count, and replace `last_func` with the
  newly supplied `func`. Do **not** run anything here — leading already fired (if
  applicable) on the burst's first call.

In both cases return `{:noreply, state}` with the key's entry stored/updated in
the state map.

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
    edge = Keyword.get(opts, :edge, :trailing)

    unless edge in @valid_edges do
      raise ArgumentError, "invalid :edge #{inspect(edge)}, expected one of #{inspect(@valid_edges)}"
    end

    GenServer.cast(__MODULE__, {:debounce, key, delay_ms, func, edge})
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_cast({:debounce, key, delay_ms, func, edge}, state) do
    # TODO
  end

  @impl true
  def handle_info({:fire, key}, state) do
    case Map.pop(state, key) do
      {nil, new_state} ->
        {:noreply, new_state}

      {entry, new_state} ->
        cond do
          entry.edge == :trailing -> run(entry.last_func)
          entry.edge == :both and entry.calls > 1 -> run(entry.last_func)
          true -> :ok
        end

        {:noreply, new_state}
    end
  end

  # Run the func off the server's reduction path.
  defp run(func), do: spawn(fn -> func.() end)
end
```