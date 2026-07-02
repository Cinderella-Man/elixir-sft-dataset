# BatchDebouncer — implement `handle_info/2`

The `BatchDebouncer` GenServer accumulates items per key during a burst and, once
the burst settles, flushes the whole ordered batch to a handler. Timers are armed
with `Process.send_after(self(), {:flush, key}, delay_ms)`, so when a key's timer
fires the server receives a `{:flush, key}` message.

Implement the `handle_info/2` clause that handles this `{:flush, key}` message. It
must pop the key's entry out of the state (removing it so the buffer is cleared and
`pending/1` returns 0 afterwards). If an entry was present, take its accumulated
`items` — which are stored newest-first — and reverse them to recover submission
order, then invoke the entry's `handler` with that ordered batch. Run the handler
off the server's reduction path (e.g. via `spawn`) so a slow or crashing handler
cannot wedge the GenServer, and reply with `{:noreply, new_state}`. If no entry was
present for the key (e.g. a stale timer), simply return `{:noreply, new_state}`
without invoking any handler.

```elixir
defmodule BatchDebouncer do
  @moduledoc """
  A `GenServer` that debounces per-key submissions but *accumulates* items during
  a burst and flushes the whole ordered batch to a handler once the burst settles.

  Each `call/4` appends its item and re-arms the key's timer. When `delay_ms`
  elapses with no further calls for the key, the most recently supplied handler
  is invoked exactly once with the list of accumulated items in submission order.
  """

  use GenServer

  @doc """
  Starts the debouncer. Accepts a `:name` option, defaulting to `BatchDebouncer`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Appends `item` to `key`'s buffer, re-arms the `delay_ms` timer, and remembers
  `handler` (a 1-arity function). Returns `:ok` promptly.
  """
  @spec call(term(), non_neg_integer(), term(), (list() -> any())) :: :ok
  def call(key, delay_ms, item, handler)
      when is_integer(delay_ms) and delay_ms >= 0 and is_function(handler, 1) do
    GenServer.cast(__MODULE__, {:submit, key, delay_ms, item, handler})
  end

  @doc "Returns the number of items currently buffered for `key` (0 if none)."
  @spec pending(term()) :: non_neg_integer()
  def pending(key), do: GenServer.call(__MODULE__, {:pending, key})

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_cast({:submit, key, delay_ms, item, handler}, state) do
    # Items are stored reversed (newest first) and reversed at flush time so we
    # never pay O(n) per append.
    items =
      case Map.get(state, key) do
        %{timer: ref, items: items} ->
          Process.cancel_timer(ref)
          [item | items]

        nil ->
          [item]
      end

    ref = Process.send_after(self(), {:flush, key}, delay_ms)
    entry = %{timer: ref, items: items, handler: handler}
    {:noreply, Map.put(state, key, entry)}
  end

  @impl true
  def handle_call({:pending, key}, _from, state) do
    count =
      case Map.get(state, key) do
        %{items: items} -> length(items)
        nil -> 0
      end

    {:reply, count, state}
  end

  @impl true
  def handle_info({:flush, key}, state) do
    # TODO
  end
end
```