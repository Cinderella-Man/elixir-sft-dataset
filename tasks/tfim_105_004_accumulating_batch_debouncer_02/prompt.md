# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule BatchDebouncerTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!(BatchDebouncer)
    :ok
  end

  # Handler that reports the batch it received, tagged so we can tell handlers apart.
  defp report(tag) do
    test = self()
    fn batch -> send(test, {tag, batch}) end
  end

  # -------------------------------------------------------
  # Accumulation + ordering
  # -------------------------------------------------------

  test "accumulates all items in a burst and flushes them once, in order" do
    # TODO
  end

  test "the most recently supplied handler receives the full batch" do
    BatchDebouncer.call("k", 150, 1, report(:h1))
    BatchDebouncer.call("k", 150, 2, report(:h2))
    BatchDebouncer.call("k", 150, 3, report(:h3))

    # h3 is the latest handler; it gets the whole ordered batch.
    assert_receive {:h3, [1, 2, 3]}, 600
    refute_received {:h1, _}
    refute_received {:h2, _}
  end

  # -------------------------------------------------------
  # Delay respected
  # -------------------------------------------------------

  test "does not flush before the delay elapses" do
    BatchDebouncer.call("k", 200, :x, report(:batch))
    refute_receive {:batch, _}, 120
    assert_receive {:batch, [:x]}, 400
  end

  test "each call resets the timer" do
    BatchDebouncer.call("k", 200, :first, report(:batch))
    Process.sleep(100)
    BatchDebouncer.call("k", 200, :second, report(:batch))

    # First item's timer (t=200) must not have fired — it was reset at t=100.
    refute_receive {:batch, _}, 150
    assert_receive {:batch, [:first, :second]}, 500
  end

  # -------------------------------------------------------
  # pending/1
  # -------------------------------------------------------

  test "pending reflects the buffer size and resets after flush" do
    assert BatchDebouncer.pending("k") == 0

    BatchDebouncer.call("k", 300, :a, report(:batch))
    BatchDebouncer.call("k", 300, :b, report(:batch))
    assert BatchDebouncer.pending("k") == 2

    assert_receive {:batch, [:a, :b]}, 600
    assert BatchDebouncer.pending("k") == 0
  end

  # -------------------------------------------------------
  # Independence + fresh batches
  # -------------------------------------------------------

  test "different keys accumulate independent batches" do
    BatchDebouncer.call("a", 150, :a1, report(:batch))
    BatchDebouncer.call("a", 150, :a2, report(:batch))
    BatchDebouncer.call("b", 150, :b1, report(:batch))

    assert_receive {:batch, [:a1, :a2]}, 500
    assert_receive {:batch, [:b1]}, 500
  end

  test "a call after a flush starts a brand-new batch" do
    BatchDebouncer.call("k", 100, :one, report(:batch))
    assert_receive {:batch, [:one]}, 400

    BatchDebouncer.call("k", 100, :two, report(:batch))
    assert_receive {:batch, [:two]}, 400
  end

  # -------------------------------------------------------
  # Contract
  # -------------------------------------------------------

  test "call/4 returns :ok promptly even when the handler would block" do
    slow = fn _batch -> Process.sleep(300) end
    {micros, :ok} = :timer.tc(fn -> BatchDebouncer.call("s", 50, :item, slow) end)
    assert micros < 100_000
  end

  test "a crashing handler leaves the server usable for later batches" do
    boom = fn _batch -> raise "boom" end
    BatchDebouncer.call("crash", 50, :bad, boom)

    BatchDebouncer.call("after", 120, :good, report(:batch))
    assert_receive {:batch, [:good]}, 600

    assert BatchDebouncer.pending("crash") == 0
    assert Process.alive?(Process.whereis(BatchDebouncer))
  end

  test "re-arming with a shorter delay flushes once and the replaced deadline never fires" do
    BatchDebouncer.call("k", 400, :a, report(:batch))
    BatchDebouncer.call("k", 60, :b, report(:batch))

    assert_receive {:batch, [:a, :b]}, 300
    assert BatchDebouncer.pending("k") == 0

    # The replaced 400ms deadline must not produce a second flush.
    refute_receive {:batch, _}, 500
  end

  test "start_link/1 registers under a custom :name alongside the default process" do
    pid = start_supervised!({BatchDebouncer, [name: :batch_debouncer_alt]}, id: :bd_alt)

    assert Process.whereis(:batch_debouncer_alt) == pid
    assert is_pid(pid)
    default = Process.whereis(BatchDebouncer)
    assert is_pid(default)
    assert default != pid
  end

  test "a call issued from inside a handler starts a fresh batch for the same key" do
    test = self()

    handler = fn batch ->
      send(test, {:first, batch})
      BatchDebouncer.call("k", 60, :again, fn b -> send(test, {:second, b}) end)
    end

    BatchDebouncer.call("k", 60, :one, handler)

    assert_receive {:first, [:one]}, 500
    assert_receive {:second, [:again]}, 500
    refute_receive {:first, _}, 200
  end

  test "identical items are appended rather than deduplicated" do
    BatchDebouncer.call("k", 150, :dup, report(:batch))
    BatchDebouncer.call("k", 150, :dup, report(:batch))

    assert BatchDebouncer.pending("k") == 2
    assert_receive {:batch, [:dup, :dup]}, 600
  end

  test "call/4 refuses a handler whose arity is not one" do
    assert_raise FunctionClauseError, fn ->
      BatchDebouncer.call("k", 50, :item, fn _a, _b -> :ok end)
    end
  end
end
```
