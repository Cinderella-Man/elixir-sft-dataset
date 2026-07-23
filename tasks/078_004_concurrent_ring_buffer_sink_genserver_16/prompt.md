# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `start_link` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

I need a module from you — `ConcurrentRingBuffer` — a fixed-size overwriting ring buffer implemented as a **GenServer** so we can share one instance safely across a bunch of concurrent processes (I'm thinking live log tail, or a metrics sink).

Push semantics are the classic ring buffer ones: once the buffer is full, the oldest item gets silently overwritten. Everything goes through the GenServer, so all operations are serialized and concurrent writers can never corrupt the buffer.

Here's the public API I need. Every function takes the server pid or registered name as its first argument:

- `ConcurrentRingBuffer.start_link(opts)` — starts the server. `opts` is a keyword list that MUST include `:capacity` (a positive integer) and MAY include `:name` for registration. Returns `{:ok, pid}`.
- `ConcurrentRingBuffer.push(server, item)` — inserts an item, overwriting the oldest when full. Returns `:ok`.
- `ConcurrentRingBuffer.to_list(server)` — returns all current items in insertion order (oldest to newest).
- `ConcurrentRingBuffer.size(server)` — returns the number of items currently stored (0 to capacity).
- `ConcurrentRingBuffer.peek_oldest(server)` — returns `{:ok, item}` for the oldest item, or `:error` if empty.
- `ConcurrentRingBuffer.peek_newest(server)` — returns `{:ok, item}` for the newest item, or `:error` if empty.
- `ConcurrentRingBuffer.flush(server)` — atomically returns all current items (oldest to newest) AND empties the buffer in a single operation, so a draining consumer never loses or double-reads items.

On the internals, I'm particular here: the server state must store items in a fixed-size tuple, pre-allocated to `capacity` slots, with integer read/write head indices that wrap around using `rem/2`. Please don't use a list or an `Enum`-grown structure as the primary store.

Send me the complete module in a single file. Stick to the Elixir standard library (plus OTP's `GenServer`) — no external dependencies.

## The module with `start_link` missing

```elixir
defmodule ConcurrentRingBuffer do
  @moduledoc """
  A fixed-size overwriting ring buffer implemented as a `GenServer`, safe to
  share across many concurrent processes (a live log tail, a metrics sink, …).

  Every mutating and reading operation is serialized through the server, so
  concurrent writers can never interleave partial updates. Push semantics
  match a classic ring buffer: when full, the oldest item is silently
  overwritten. `flush/1` atomically drains the buffer — returning everything
  and resetting to empty in one call — so a consumer never loses or
  double-reads items.

  Server state stores items in a fixed-size tuple pre-allocated to `capacity`
  slots, with integer `read`/`write` head indices that wrap around via
  `rem/2`, plus an independent `size` capped at `capacity`.
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  def start_link(opts) when is_list(opts) do
    # TODO
  end

  @doc "Inserts `item`, overwriting the oldest when full. Returns `:ok`."
  @spec push(GenServer.server(), any()) :: :ok
  def push(server, item), do: GenServer.call(server, {:push, item})

  @doc "Returns all live items in insertion order (oldest → newest)."
  @spec to_list(GenServer.server()) :: list()
  def to_list(server), do: GenServer.call(server, :to_list)

  @doc "Returns the number of items currently stored (0..capacity)."
  @spec size(GenServer.server()) :: non_neg_integer()
  def size(server), do: GenServer.call(server, :size)

  @doc "Returns `{:ok, item}` for the oldest item, or `:error` if empty."
  @spec peek_oldest(GenServer.server()) :: {:ok, any()} | :error
  def peek_oldest(server), do: GenServer.call(server, :peek_oldest)

  @doc "Returns `{:ok, item}` for the newest item, or `:error` if empty."
  @spec peek_newest(GenServer.server()) :: {:ok, any()} | :error
  def peek_newest(server), do: GenServer.call(server, :peek_newest)

  @doc """
  Atomically returns all live items (oldest → newest) and empties the buffer.
  """
  @spec flush(GenServer.server()) :: list()
  def flush(server), do: GenServer.call(server, :flush)

  # ---------------------------------------------------------------------------
  # Server callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(capacity) when is_integer(capacity) and capacity > 0 do
    {:ok, fresh_state(capacity)}
  end

  @impl true
  def handle_call({:push, item}, _from, state) do
    {:reply, :ok, do_push(state, item)}
  end

  def handle_call(:to_list, _from, state) do
    {:reply, do_to_list(state), state}
  end

  def handle_call(:size, _from, state) do
    {:reply, state.size, state}
  end

  def handle_call(:peek_oldest, _from, state) do
    {:reply, do_peek_oldest(state), state}
  end

  def handle_call(:peek_newest, _from, state) do
    {:reply, do_peek_newest(state), state}
  end

  def handle_call(:flush, _from, state) do
    {:reply, do_to_list(state), fresh_state(state.capacity)}
  end

  # ---------------------------------------------------------------------------
  # Internal ring-buffer logic (pure, over the state map)
  # ---------------------------------------------------------------------------

  defp fresh_state(capacity) do
    %{
      capacity: capacity,
      store: :erlang.make_tuple(capacity, nil),
      read: 0,
      write: 0,
      size: 0
    }
  end

  defp do_push(state, item) do
    %{capacity: cap, store: store, read: read, write: write, size: size} = state
    new_store = :erlang.setelement(write + 1, store, item)
    new_write = rem(write + 1, cap)

    if size == cap do
      %{state | store: new_store, write: new_write, read: rem(read + 1, cap)}
    else
      %{state | store: new_store, write: new_write, size: size + 1}
    end
  end

  defp do_to_list(%{size: 0}), do: []

  defp do_to_list(%{capacity: cap, store: store, read: read, size: size}) do
    Enum.map(0..(size - 1), fn offset ->
      :erlang.element(rem(read + offset, cap) + 1, store)
    end)
  end

  defp do_peek_oldest(%{size: 0}), do: :error

  defp do_peek_oldest(%{store: store, read: read}) do
    {:ok, :erlang.element(read + 1, store)}
  end

  defp do_peek_newest(%{size: 0}), do: :error

  defp do_peek_newest(%{capacity: cap, store: store, write: write}) do
    newest_index = rem(write - 1 + cap, cap)
    {:ok, :erlang.element(newest_index + 1, store)}
  end
end
```

Give me only the complete implementation of `start_link` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
