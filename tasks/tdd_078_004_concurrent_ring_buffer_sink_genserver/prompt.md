# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

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
    {:ok, pid} = ConcurrentRingBuffer.start_link(capacity: 4)
    assert :ok = ConcurrentRingBuffer.push(pid, 1)
    assert ConcurrentRingBuffer.size(pid) == 1
    ConcurrentRingBuffer.push(pid, 2)
    ConcurrentRingBuffer.push(pid, 3)
    assert ConcurrentRingBuffer.size(pid) == 3
    assert ConcurrentRingBuffer.to_list(pid) == [1, 2, 3]
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

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
