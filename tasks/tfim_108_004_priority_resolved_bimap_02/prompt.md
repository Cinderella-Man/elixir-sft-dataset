# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule PriorityBiMap do
  @moduledoc """
  A GenServer maintaining a bijective bidirectional mapping where each pair
  carries an integer priority and conflicts are resolved by priority.

  A `put/4` may conflict with the pair currently at `key` and/or the pair
  currently at `value`. It succeeds only when its priority is strictly greater
  than every conflicting pair's priority, in which case the conflicting pairs are
  evicted and reported; otherwise (including ties) it is rejected and nothing
  changes. Re-putting the exact same pair simply updates its stored priority.

  Keys and values may be any term; priorities are integers.
  """

  use GenServer

  ## Client API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, :ok, [name: name] ++ opts)
  end

  @spec put(GenServer.server(), term(), term(), integer()) ::
          {:ok, [{term(), term()}]} | {:error, :rejected}
  def put(name, key, value, priority) do
    GenServer.call(name, {:put, key, value, priority})
  end

  @spec get_by_key(GenServer.server(), term()) :: {:ok, term()} | :error
  def get_by_key(name, key), do: GenServer.call(name, {:get_by_key, key})

  @spec get_by_value(GenServer.server(), term()) :: {:ok, term()} | :error
  def get_by_value(name, value), do: GenServer.call(name, {:get_by_value, value})

  @spec priority(GenServer.server(), term()) :: {:ok, integer()} | :error
  def priority(name, key), do: GenServer.call(name, {:priority, key})

  @spec delete(GenServer.server(), term()) :: :ok
  def delete(name, key), do: GenServer.call(name, {:delete, key})

  ## Server callbacks

  @impl true
  def init(:ok) do
    # forward: key => value, reverse: value => key, prio: key => priority
    {:ok, %{forward: %{}, reverse: %{}, prio: %{}}}
  end

  @impl true
  def handle_call({:put, key, value, priority}, _from, state) do
    %{forward: f, reverse: r, prio: p} = state

    # The pair currently sitting at `key`, if it binds a *different* value.
    key_conflict =
      case Map.fetch(f, key) do
        {:ok, ^value} -> nil
        {:ok, oldv} -> {key, oldv, Map.fetch!(p, key)}
        :error -> nil
      end

    # The pair currently sitting at `value`, if it binds a *different* key.
    value_conflict =
      case Map.fetch(r, value) do
        {:ok, ^key} -> nil
        {:ok, oldk} -> {oldk, value, Map.fetch!(p, oldk)}
        :error -> nil
      end

    conflicts = Enum.reject([key_conflict, value_conflict], &is_nil/1)

    cond do
      conflicts == [] ->
        # Same pair (priority update) or a fully free slot: install.
        {:reply, {:ok, []}, install(state, key, value, priority)}

      priority > Enum.max(Enum.map(conflicts, fn {_k, _v, cp} -> cp end)) ->
        state = Enum.reduce(conflicts, state, fn {ck, cv, _cp}, acc -> evict(acc, ck, cv) end)
        evicted = Enum.map(conflicts, fn {ck, cv, _cp} -> {ck, cv} end)
        {:reply, {:ok, evicted}, install(state, key, value, priority)}

      true ->
        {:reply, {:error, :rejected}, state}
    end
  end

  def handle_call({:get_by_key, key}, _from, state) do
    {:reply, Map.fetch(state.forward, key), state}
  end

  def handle_call({:get_by_value, value}, _from, state) do
    {:reply, Map.fetch(state.reverse, value), state}
  end

  def handle_call({:priority, key}, _from, state) do
    {:reply, Map.fetch(state.prio, key), state}
  end

  def handle_call({:delete, key}, _from, state) do
    case Map.fetch(state.forward, key) do
      {:ok, value} -> {:reply, :ok, evict(state, key, value)}
      :error -> {:reply, :ok, state}
    end
  end

  ## Helpers

  defp install(state, key, value, priority) do
    %{
      state
      | forward: Map.put(state.forward, key, value),
        reverse: Map.put(state.reverse, value, key),
        prio: Map.put(state.prio, key, priority)
    }
  end

  defp evict(state, key, value) do
    %{
      state
      | forward: Map.delete(state.forward, key),
        reverse: Map.delete(state.reverse, value),
        prio: Map.delete(state.prio, key)
    }
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule PriorityBiMapTest do
  use ExUnit.Case, async: false

  setup do
    name = :"pbm_#{System.unique_integer([:positive])}"
    pid = start_supervised!({PriorityBiMap, name: name})
    %{bm: name, pid: pid}
  end

  # -------------------------------------------------------
  # Basic install and lookup
  # -------------------------------------------------------

  test "put then look up in both directions", %{bm: bm} do
    # TODO
  end

  test "missing key/value/priority return :error", %{bm: bm} do
    assert :error = PriorityBiMap.get_by_key(bm, :nope)
    assert :error = PriorityBiMap.get_by_value(bm, 999)
    assert :error = PriorityBiMap.priority(bm, :nope)
  end

  test "non-conflicting pairs install cleanly", %{bm: bm} do
    assert {:ok, []} = PriorityBiMap.put(bm, :a, 1, 5)
    assert {:ok, []} = PriorityBiMap.put(bm, :b, 2, 5)

    assert {:ok, 1} = PriorityBiMap.get_by_key(bm, :a)
    assert {:ok, 2} = PriorityBiMap.get_by_key(bm, :b)
  end

  # -------------------------------------------------------
  # Same-pair re-put updates priority
  # -------------------------------------------------------

  test "re-putting the same pair updates its priority and displaces nothing", %{bm: bm} do
    assert {:ok, []} = PriorityBiMap.put(bm, :x, 9, 3)
    assert {:ok, []} = PriorityBiMap.put(bm, :x, 9, 7)

    assert {:ok, 9} = PriorityBiMap.get_by_key(bm, :x)
    assert {:ok, 7} = PriorityBiMap.priority(bm, :x)
  end

  # -------------------------------------------------------
  # Rejection on insufficient priority
  # -------------------------------------------------------

  test "lower-priority put across two existing pairs is rejected and changes nothing", %{bm: bm} do
    PriorityBiMap.put(bm, :a, 1, 10)
    PriorityBiMap.put(bm, :b, 2, 10)

    # :a wants value 2 (held by :b) — conflicts with (a,1,10) and (b,2,10).
    assert {:error, :rejected} = PriorityBiMap.put(bm, :a, 2, 5)

    # Nothing moved.
    assert {:ok, 1} = PriorityBiMap.get_by_key(bm, :a)
    assert {:ok, 2} = PriorityBiMap.get_by_key(bm, :b)
    assert {:ok, :a} = PriorityBiMap.get_by_value(bm, 1)
    assert {:ok, :b} = PriorityBiMap.get_by_value(bm, 2)
    assert {:ok, 10} = PriorityBiMap.priority(bm, :a)
  end

  test "equal priority is a tie and is rejected", %{bm: bm} do
    PriorityBiMap.put(bm, :m, 1, 5)

    # New key :n wants value 1 (held by :m at prio 5). Tie -> rejected.
    assert {:error, :rejected} = PriorityBiMap.put(bm, :n, 1, 5)

    assert {:ok, :m} = PriorityBiMap.get_by_value(bm, 1)
    assert :error = PriorityBiMap.get_by_key(bm, :n)
  end

  # -------------------------------------------------------
  # Acceptance with displacement
  # -------------------------------------------------------

  test "single value-side conflict is displaced when priority wins", %{bm: bm} do
    PriorityBiMap.put(bm, :p, 1, 10)

    # :q wants value 1 (held by :p). 20 > 10 -> accept, displace (p,1).
    assert {:ok, evicted} = PriorityBiMap.put(bm, :q, 1, 20)
    assert evicted == [{:p, 1}]

    assert :error = PriorityBiMap.get_by_key(bm, :p)
    assert {:ok, :q} = PriorityBiMap.get_by_value(bm, 1)
    assert {:ok, 1} = PriorityBiMap.get_by_key(bm, :q)
    assert {:ok, 20} = PriorityBiMap.priority(bm, :q)
  end

  test "double conflict displaces both pairs when priority wins", %{bm: bm} do
    PriorityBiMap.put(bm, :a, 1, 10)
    PriorityBiMap.put(bm, :b, 2, 10)

    # :a wants value 2. Conflicts: (a,1,10) key-side and (b,2,10) value-side.
    assert {:ok, evicted} = PriorityBiMap.put(bm, :a, 2, 15)
    assert Enum.sort(evicted) == Enum.sort([{:a, 1}, {:b, 2}])

    # Surviving pair is consistent both ways.
    assert {:ok, 2} = PriorityBiMap.get_by_key(bm, :a)
    assert {:ok, :a} = PriorityBiMap.get_by_value(bm, 2)
    # Both old associations are gone.
    assert :error = PriorityBiMap.get_by_value(bm, 1)
    assert :error = PriorityBiMap.get_by_key(bm, :b)
    assert {:ok, 15} = PriorityBiMap.priority(bm, :a)
  end

  # -------------------------------------------------------
  # Delete and reuse
  # -------------------------------------------------------

  test "delete removes both directions and the priority", %{bm: bm} do
    PriorityBiMap.put(bm, :a, 1, 5)
    assert :ok = PriorityBiMap.delete(bm, :a)

    assert :error = PriorityBiMap.get_by_key(bm, :a)
    assert :error = PriorityBiMap.get_by_value(bm, 1)
    assert :error = PriorityBiMap.priority(bm, :a)
  end

  test "delete of an absent key is a harmless no-op", %{bm: bm} do
    assert :ok = PriorityBiMap.delete(bm, :ghost)
    PriorityBiMap.put(bm, :a, 1, 5)
    assert :ok = PriorityBiMap.delete(bm, :ghost)
    assert {:ok, 1} = PriorityBiMap.get_by_key(bm, :a)
  end

  test "a freed key/value can be re-used at any priority", %{bm: bm} do
    PriorityBiMap.put(bm, :a, 1, 10)
    PriorityBiMap.delete(bm, :a)

    # Value 1 is free again, so even a low priority installs cleanly.
    assert {:ok, []} = PriorityBiMap.put(bm, :b, 1, 1)
    assert {:ok, :b} = PriorityBiMap.get_by_value(bm, 1)
  end

  # -------------------------------------------------------
  # Bijection consistency across a mixed sequence
  # -------------------------------------------------------

  test "bijection holds across a mixed accept/reject sequence", %{bm: bm} do
    ops = [
      {:a, 1, 10},
      {:b, 2, 10},
      {:c, 3, 5},
      {:a, 2, 3},
      {:a, 2, 20},
      {:d, 3, 1},
      {:e, 3, 9},
      {:b, 1, 25}
    ]

    Enum.each(ops, fn {k, v, p} -> PriorityBiMap.put(bm, k, v, p) end)

    keys = [:a, :b, :c, :d, :e]
    values = [1, 2, 3]

    for k <- keys do
      case PriorityBiMap.get_by_key(bm, k) do
        {:ok, v} -> assert {:ok, ^k} = PriorityBiMap.get_by_value(bm, v)
        :error -> :ok
      end
    end

    for v <- values do
      case PriorityBiMap.get_by_value(bm, v) do
        {:ok, k} -> assert {:ok, ^v} = PriorityBiMap.get_by_key(bm, k)
        :error -> :ok
      end
    end
  end
end
```
