# BatchDebouncer — implement `handle_call/3`

`BatchDebouncer` is a `GenServer` that debounces per-key submissions but
*accumulates* items during a burst and flushes the whole ordered batch to a
handler once the burst settles. The rest of the module (public API, `init/1`,
`handle_cast/2`, and `handle_info/2`) is already written for you.

Implement the `handle_call/3` clause that backs `BatchDebouncer.pending/1`. It
receives `{:pending, key}` and must reply synchronously with the number of items
currently buffered for `key`. Look up `key` in the state map: if there is an
entry, reply with the length of its `:items` list (items are stored reversed
internally, but the count is the same either way); if there is no entry for the
key, reply with `0`. The state must be returned unchanged.

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
    # TODO
  end

  @impl true
  def handle_info({:flush, key}, state) do
    case Map.pop(state, key) do
      {%{items: items, handler: handler}, new_state} ->
        batch = Enum.reverse(items)
        spawn(fn -> handler.(batch) end)
        {:noreply, new_state}

      {nil, new_state} ->
        {:noreply, new_state}
    end
  end
end
```