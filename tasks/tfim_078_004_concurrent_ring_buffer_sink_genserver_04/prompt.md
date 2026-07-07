# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

  @doc """
  Starts the server. `opts` must include `:capacity` (positive integer) and
  may include `:name` for registration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {capacity, opts} = Keyword.pop(opts, :capacity)
    GenServer.start_link(__MODULE__, capacity, opts)
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

## Test harness — implement the `# TODO` test

```elixir
defmodule ConcurrentRingBufferTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Construction
  # -------------------------------------------------------

  test "new server is empty" do
    {:ok, pid} = ConcurrentRingBuffer.start_link(capacity: 4)
    assert ConcurrentRingBuffer.size(pid) == 0
    assert ConcurrentRingBuffer.to_list(pid) == []
    assert :error = ConcurrentRingBuffer.peek_oldest(pid)
    assert :error = ConcurrentRingBuffer.peek_newest(pid)
  end

  test "can be registered by name" do
    {:ok, _pid} = ConcurrentRingBuffer.start_link(capacity: 3, name: :ring_named)
    ConcurrentRingBuffer.push(:ring_named, :a)
    ConcurrentRingBuffer.push(:ring_named, :b)
    assert ConcurrentRingBuffer.to_list(:ring_named) == [:a, :b]
  end

  # -------------------------------------------------------
  # Basic push / overwrite
  # -------------------------------------------------------

  test "push grows size up to capacity" do
    # TODO
  end

  test "oldest item is overwritten when full" do
    {:ok, pid} = ConcurrentRingBuffer.start_link(capacity: 3)
    Enum.each([1, 2, 3, 4], &ConcurrentRingBuffer.push(pid, &1))
    assert ConcurrentRingBuffer.size(pid) == 3
    assert ConcurrentRingBuffer.to_list(pid) == [2, 3, 4]
    assert {:ok, 2} = ConcurrentRingBuffer.peek_oldest(pid)
    assert {:ok, 4} = ConcurrentRingBuffer.peek_newest(pid)
  end

  test "many overwrites keep only the last capacity items" do
    {:ok, pid} = ConcurrentRingBuffer.start_link(capacity: 4)
    Enum.each(1..20, &ConcurrentRingBuffer.push(pid, &1))
    assert ConcurrentRingBuffer.size(pid) == 4
    assert ConcurrentRingBuffer.to_list(pid) == [17, 18, 19, 20]
  end

  # -------------------------------------------------------
  # Flush
  # -------------------------------------------------------

  test "flush returns current items and empties the buffer" do
    {:ok, pid} = ConcurrentRingBuffer.start_link(capacity: 5)
    Enum.each([:a, :b, :c], &ConcurrentRingBuffer.push(pid, &1))

    assert ConcurrentRingBuffer.flush(pid) == [:a, :b, :c]
    assert ConcurrentRingBuffer.size(pid) == 0
    assert ConcurrentRingBuffer.to_list(pid) == []
    assert :error = ConcurrentRingBuffer.peek_oldest(pid)
  end

  test "flush on an empty buffer returns []" do
    {:ok, pid} = ConcurrentRingBuffer.start_link(capacity: 3)
    assert ConcurrentRingBuffer.flush(pid) == []
  end

  test "buffer is usable again after flush (wraparound preserved)" do
    {:ok, pid} = ConcurrentRingBuffer.start_link(capacity: 3)
    Enum.each([1, 2, 3, 4], &ConcurrentRingBuffer.push(pid, &1))
    assert ConcurrentRingBuffer.flush(pid) == [2, 3, 4]

    Enum.each([5, 6], &ConcurrentRingBuffer.push(pid, &1))
    assert ConcurrentRingBuffer.to_list(pid) == [5, 6]
  end

  # -------------------------------------------------------
  # Capacity of 1
  # -------------------------------------------------------

  test "capacity-1 server always holds exactly one item" do
    {:ok, pid} = ConcurrentRingBuffer.start_link(capacity: 1)
    ConcurrentRingBuffer.push(pid, :only)
    assert ConcurrentRingBuffer.to_list(pid) == [:only]
    ConcurrentRingBuffer.push(pid, :replaced)
    assert ConcurrentRingBuffer.to_list(pid) == [:replaced]
    assert {:ok, :replaced} = ConcurrentRingBuffer.peek_oldest(pid)
    assert {:ok, :replaced} = ConcurrentRingBuffer.peek_newest(pid)
  end

  # -------------------------------------------------------
  # Concurrency
  # -------------------------------------------------------

  test "concurrent writers never corrupt the buffer" do
    {:ok, pid} = ConcurrentRingBuffer.start_link(capacity: 10)

    1..1000
    |> Task.async_stream(fn i -> ConcurrentRingBuffer.push(pid, i) end,
      max_concurrency: 50,
      ordered: false
    )
    |> Stream.run()

    assert ConcurrentRingBuffer.size(pid) == 10
    list = ConcurrentRingBuffer.to_list(pid)
    assert length(list) == 10
    assert Enum.all?(list, fn x -> is_integer(x) and x in 1..1000 end)
    # No duplicate slots / corruption: all held values are distinct.
    assert length(Enum.uniq(list)) == 10
  end

  test "concurrent readers and writers stay consistent" do
    {:ok, pid} = ConcurrentRingBuffer.start_link(capacity: 8)

    writers =
      Task.async(fn ->
        Enum.each(1..500, &ConcurrentRingBuffer.push(pid, &1))
      end)

    readers =
      Task.async(fn ->
        Enum.map(1..200, fn _ ->
          list = ConcurrentRingBuffer.to_list(pid)
          # size of any snapshot must never exceed capacity
          assert length(list) <= 8
          length(list)
        end)
      end)

    Task.await(writers)
    Task.await(readers)

    assert ConcurrentRingBuffer.size(pid) == 8
  end

  # -------------------------------------------------------
  # Type variety
  # -------------------------------------------------------

  test "works with mixed value types" do
    {:ok, pid} = ConcurrentRingBuffer.start_link(capacity: 5)
    Enum.each([42, "hello", :atom, {:tuple, 1}, [1, 2, 3]], &ConcurrentRingBuffer.push(pid, &1))
    assert ConcurrentRingBuffer.to_list(pid) == [42, "hello", :atom, {:tuple, 1}, [1, 2, 3]]
  end
end
```
