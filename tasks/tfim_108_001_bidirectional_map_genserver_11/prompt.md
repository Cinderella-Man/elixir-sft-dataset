# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule BiMap do
  @moduledoc """
  A GenServer maintaining a bidirectional (bijective) mapping between keys and
  values.

  Every key maps to exactly one value and every value maps back to exactly one
  key. The bijection invariant is enforced on every `put/3`: reassigning a key
  orphans its old value, and reassigning a value orphans its old key, so the
  forward and reverse maps stay perfectly consistent.

  Keys and values may be any term.
  """

  use GenServer

  ## Client API

  @doc """
  Starts the BiMap process.

  Accepts a `:name` option used to register the process. All other functions
  accept that name (or any valid GenServer server reference) as their first
  argument.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, :ok, [name: name] ++ opts)
  end

  @doc """
  Inserts or updates the association between `key` and `value`, preserving the
  bijection invariant. Always returns `:ok`.
  """
  @spec put(GenServer.server(), term(), term()) :: :ok
  def put(name, key, value) do
    GenServer.call(name, {:put, key, value})
  end

  @doc """
  Returns `{:ok, value}` if `key` is present, otherwise `:error`.
  """
  @spec get_by_key(GenServer.server(), term()) :: {:ok, term()} | :error
  def get_by_key(name, key) do
    GenServer.call(name, {:get_by_key, key})
  end

  @doc """
  Returns `{:ok, key}` if `value` is present, otherwise `:error`.
  """
  @spec get_by_value(GenServer.server(), term()) :: {:ok, term()} | :error
  def get_by_value(name, value) do
    GenServer.call(name, {:get_by_value, value})
  end

  @doc """
  Removes `key` and its associated value in both directions. Always returns
  `:ok`, even when `key` is absent.
  """
  @spec delete(GenServer.server(), term()) :: :ok
  def delete(name, key) do
    GenServer.call(name, {:delete, key})
  end

  ## Server callbacks

  @impl true
  def init(:ok) do
    # forward: key => value, reverse: value => key
    {:ok, %{forward: %{}, reverse: %{}}}
  end

  @impl true
  def handle_call({:put, key, value}, _from, state) do
    %{forward: forward, reverse: reverse} = state

    # If key currently points to a different value, orphan that old value.
    reverse =
      case Map.fetch(forward, key) do
        {:ok, ^value} -> reverse
        {:ok, old_value} -> Map.delete(reverse, old_value)
        :error -> reverse
      end

    # If value currently points to a different key, orphan that old key.
    forward =
      case Map.fetch(reverse, value) do
        {:ok, ^key} -> forward
        {:ok, old_key} -> Map.delete(forward, old_key)
        :error -> forward
      end

    forward = Map.put(forward, key, value)
    reverse = Map.put(reverse, value, key)

    {:reply, :ok, %{state | forward: forward, reverse: reverse}}
  end

  @impl true
  def handle_call({:get_by_key, key}, _from, state) do
    {:reply, Map.fetch(state.forward, key), state}
  end

  @impl true
  def handle_call({:get_by_value, value}, _from, state) do
    {:reply, Map.fetch(state.reverse, value), state}
  end

  @impl true
  def handle_call({:delete, key}, _from, state) do
    %{forward: forward, reverse: reverse} = state

    case Map.fetch(forward, key) do
      {:ok, value} ->
        new_state = %{
          state
          | forward: Map.delete(forward, key),
            reverse: Map.delete(reverse, value)
        }

        {:reply, :ok, new_state}

      :error ->
        {:reply, :ok, state}
    end
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule BiMapTest do
  use ExUnit.Case, async: false

  setup do
    name = :"bimap_#{System.unique_integer([:positive])}"
    pid = start_supervised!({BiMap, name: name})
    %{bm: name, pid: pid}
  end

  # -------------------------------------------------------
  # Basic put / get in both directions
  # -------------------------------------------------------

  test "put then look up in both directions", %{bm: bm} do
    assert :ok = BiMap.put(bm, :a, 1)

    assert {:ok, 1} = BiMap.get_by_key(bm, :a)
    assert {:ok, :a} = BiMap.get_by_value(bm, 1)
  end

  test "missing key and missing value return :error", %{bm: bm} do
    assert :error = BiMap.get_by_key(bm, :nope)
    assert :error = BiMap.get_by_value(bm, 999)
  end

  test "multiple independent pairs coexist", %{bm: bm} do
    BiMap.put(bm, :a, 1)
    BiMap.put(bm, :b, 2)
    BiMap.put(bm, :c, 3)

    assert {:ok, 1} = BiMap.get_by_key(bm, :a)
    assert {:ok, 2} = BiMap.get_by_key(bm, :b)
    assert {:ok, 3} = BiMap.get_by_key(bm, :c)

    assert {:ok, :a} = BiMap.get_by_value(bm, 1)
    assert {:ok, :b} = BiMap.get_by_value(bm, 2)
    assert {:ok, :c} = BiMap.get_by_value(bm, 3)
  end

  test "keys and values may be arbitrary terms", %{bm: bm} do
    BiMap.put(bm, "string_key", {:tuple, "value"})
    BiMap.put(bm, {:composite, 1}, [1, 2, 3])

    assert {:ok, {:tuple, "value"}} = BiMap.get_by_key(bm, "string_key")
    assert {:ok, "string_key"} = BiMap.get_by_value(bm, {:tuple, "value"})
    assert {:ok, [1, 2, 3]} = BiMap.get_by_key(bm, {:composite, 1})
    assert {:ok, {:composite, 1}} = BiMap.get_by_value(bm, [1, 2, 3])
  end

  # -------------------------------------------------------
  # Duplicate value with a different key removes old key
  # -------------------------------------------------------

  test "putting a duplicate value under a new key evicts the old key", %{bm: bm} do
    BiMap.put(bm, :a, 1)
    BiMap.put(bm, :b, 1)

    # Old key is gone
    assert :error = BiMap.get_by_key(bm, :a)

    # Value now points to the new key
    assert {:ok, 1} = BiMap.get_by_key(bm, :b)
    assert {:ok, :b} = BiMap.get_by_value(bm, 1)
  end

  # -------------------------------------------------------
  # Updating a key's value orphans the old value
  # -------------------------------------------------------

  test "reassigning a key to a new value removes the old reverse mapping", %{bm: bm} do
    BiMap.put(bm, :a, 1)
    BiMap.put(bm, :a, 2)

    # Old value's reverse mapping is gone
    assert :error = BiMap.get_by_value(bm, 1)

    # Key now maps to the new value, both directions consistent
    assert {:ok, 2} = BiMap.get_by_key(bm, :a)
    assert {:ok, :a} = BiMap.get_by_value(bm, 2)
  end

  # -------------------------------------------------------
  # The hard bijection case: key and value both already used
  # -------------------------------------------------------

  test "reassigning across existing entries preserves the bijection", %{bm: bm} do
    BiMap.put(bm, :a, 1)
    BiMap.put(bm, :b, 2)

    # :a wants value 2, which currently belongs to :b
    BiMap.put(bm, :a, 2)

    # :b lost its value (value 2 was reassigned to :a)
    assert :error = BiMap.get_by_key(bm, :b)
    # :a's old value 1 is orphaned
    assert :error = BiMap.get_by_value(bm, 1)

    # Surviving pair is consistent both ways
    assert {:ok, 2} = BiMap.get_by_key(bm, :a)
    assert {:ok, :a} = BiMap.get_by_value(bm, 2)
  end

  # -------------------------------------------------------
  # Idempotent re-put of the same pair
  # -------------------------------------------------------

  test "putting the same pair twice leaves it intact", %{bm: bm} do
    BiMap.put(bm, :a, 1)
    BiMap.put(bm, :a, 1)

    assert {:ok, 1} = BiMap.get_by_key(bm, :a)
    assert {:ok, :a} = BiMap.get_by_value(bm, 1)
  end

  # -------------------------------------------------------
  # Delete
  # -------------------------------------------------------

  test "delete removes both directions", %{bm: bm} do
    BiMap.put(bm, :a, 1)
    assert :ok = BiMap.delete(bm, :a)

    assert :error = BiMap.get_by_key(bm, :a)
    assert :error = BiMap.get_by_value(bm, 1)
  end

  test "delete of an absent key is a harmless no-op", %{bm: bm} do
    # TODO
  end

  test "after delete the freed key and value can be reused", %{bm: bm} do
    BiMap.put(bm, :a, 1)
    BiMap.delete(bm, :a)

    BiMap.put(bm, :a, 2)
    BiMap.put(bm, :b, 1)

    assert {:ok, 2} = BiMap.get_by_key(bm, :a)
    assert {:ok, :b} = BiMap.get_by_value(bm, 1)
    assert {:ok, 1} = BiMap.get_by_key(bm, :b)
    assert {:ok, :a} = BiMap.get_by_value(bm, 2)
  end

  # -------------------------------------------------------
  # Invariant fuzz: a scripted sequence must stay a bijection
  # -------------------------------------------------------

  test "bijection invariant holds across a mixed operation sequence", %{bm: bm} do
    ops = [
      {:put, :a, 1},
      {:put, :b, 2},
      {:put, :c, 3},
      {:put, :a, 2},
      {:put, :d, 3},
      {:delete, :b},
      {:put, :e, 1},
      {:put, :a, 5},
      {:delete, :z},
      {:put, :f, 5}
    ]

    keys = [:a, :b, :c, :d, :e, :f, :z]
    values = [1, 2, 3, 4, 5, 6]

    Enum.each(ops, fn
      {:put, k, v} -> assert :ok = BiMap.put(bm, k, v)
      {:delete, k} -> assert :ok = BiMap.delete(bm, k)
    end)

    # Forward -> reverse consistency for every key that survived.
    for k <- keys do
      case BiMap.get_by_key(bm, k) do
        {:ok, v} -> assert {:ok, ^k} = BiMap.get_by_value(bm, v)
        :error -> :ok
      end
    end

    # Reverse -> forward consistency for every value that survived.
    for v <- values do
      case BiMap.get_by_value(bm, v) do
        {:ok, k} -> assert {:ok, ^v} = BiMap.get_by_key(bm, k)
        :error -> :ok
      end
    end

    # No value maps to more than one key: collect surviving (value -> key)
    # pairs and ensure keys are unique across distinct values.
    surviving =
      for v <- values, match?({:ok, _}, BiMap.get_by_value(bm, v)) do
        {:ok, k} = BiMap.get_by_value(bm, v)
        {v, k}
      end

    surviving_keys = Enum.map(surviving, fn {_v, k} -> k end)
    assert length(surviving_keys) == length(Enum.uniq(surviving_keys))
  end

  test "every function accepts a raw pid as the server reference", %{pid: pid} do
    assert :ok = BiMap.put(pid, :a, 1)
    assert {:ok, 1} = BiMap.get_by_key(pid, :a)
    assert {:ok, :a} = BiMap.get_by_value(pid, 1)

    assert :ok = BiMap.put(pid, :b, 1)
    assert :error = BiMap.get_by_key(pid, :a)
    assert {:ok, :b} = BiMap.get_by_value(pid, 1)

    assert :ok = BiMap.delete(pid, :b)
    assert :error = BiMap.get_by_key(pid, :b)
    assert :error = BiMap.get_by_value(pid, 1)
  end

  test "start_link with a :name option returns {:ok, pid} and registers that name" do
    name = :"bimap_started_#{System.unique_integer([:positive])}"

    assert {:ok, pid} = BiMap.start_link(name: name)
    assert is_pid(pid)
    assert Process.whereis(name) == pid

    assert :ok = BiMap.put(name, :k, :v)
    assert {:ok, :v} = BiMap.get_by_key(name, :k)

    GenServer.stop(pid)
  end

  test "bijection survives terms used as both key and value", %{bm: bm} do
    assert :ok = BiMap.put(bm, :a, :b)
    assert :ok = BiMap.put(bm, :b, :a)

    assert {:ok, :b} = BiMap.get_by_key(bm, :a)
    assert {:ok, :a} = BiMap.get_by_value(bm, :b)
    assert {:ok, :a} = BiMap.get_by_key(bm, :b)
    assert {:ok, :b} = BiMap.get_by_value(bm, :a)

    # Reassign :a to itself: the old value :b is orphaned as a value, but :b
    # keeps its own forward entry :b -> :a.
    assert :ok = BiMap.put(bm, :a, :a)

    assert {:ok, :a} = BiMap.get_by_key(bm, :a)
    assert {:ok, :a} = BiMap.get_by_value(bm, :a)
    assert :error = BiMap.get_by_key(bm, :b)
    assert :error = BiMap.get_by_value(bm, :b)
  end

  # -------------------------------------------------------
  # Which entry an overlapping term loses: the owner of the
  # conflicting value, not every entry naming that term
  # -------------------------------------------------------

  test "self-mapping a key evicts the key that owned that term as a value", %{bm: bm} do
    assert :ok = BiMap.put(bm, :a, :b)
    assert :ok = BiMap.put(bm, :b, :a)
    assert :ok = BiMap.put(bm, :c, :d)

    # Value :a currently belongs to key :b, so putting {:a, :a} reassigns that
    # value to key :a and :b's whole mapping is removed. :a's old value :b is
    # orphaned at the same time, leaving :b absent in both directions.
    assert :ok = BiMap.put(bm, :a, :a)

    assert :error = BiMap.get_by_key(bm, :b)
    assert :error = BiMap.get_by_value(bm, :b)

    # The surviving self-pair is consistent both ways.
    assert {:ok, :a} = BiMap.get_by_key(bm, :a)
    assert {:ok, :a} = BiMap.get_by_value(bm, :a)

    # An unrelated pair is untouched by the eviction.
    assert {:ok, :d} = BiMap.get_by_key(bm, :c)
    assert {:ok, :c} = BiMap.get_by_value(bm, :d)
  end

  test "value eviction removes the owning key while the same term survives as a key",
       %{bm: bm} do
    assert :ok = BiMap.put(bm, :a, :b)
    assert :ok = BiMap.put(bm, :b, :c)

    # Value :b belongs to key :a, so key :a loses its mapping. Term :b is also
    # a key in its own right; that entry :b -> :c is not the owner of value :b
    # and stays put.
    assert :ok = BiMap.put(bm, :c, :b)

    assert :error = BiMap.get_by_key(bm, :a)
    assert :error = BiMap.get_by_value(bm, :a)

    assert {:ok, :c} = BiMap.get_by_key(bm, :b)
    assert {:ok, :b} = BiMap.get_by_value(bm, :c)

    assert {:ok, :b} = BiMap.get_by_key(bm, :c)
    assert {:ok, :c} = BiMap.get_by_value(bm, :b)
  end
end
```
