# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule IntervalRegistry do
  @moduledoc """
  A concurrent, process-backed interval store.

  The server holds an augmented AVL interval tree keyed by `{start, finish, id}`
  (ids are unique, so keys are unique and `remove/2` is an O(log n) balanced
  deletion). Each node caches the maximum `finish` of its subtree so overlap,
  enclosing, and stabbing-count queries prune branches instead of scanning.

  All state lives inside the GenServer, so concurrent inserts and removes from
  many client processes are serialized and stay consistent. Two intervals
  overlap when they share at least one point (`{1, 3}` and `{3, 5}` overlap).
  """

  use GenServer

  @type interval :: {integer(), integer()}

  # -------------------------------------------------------------------------
  # Client API
  # -------------------------------------------------------------------------

  @doc """
  Starts the registry server.

  Accepts standard `GenServer` options (e.g. `:name`) and returns
  `{:ok, pid}` on success.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, :ok, opts)

  @doc """
  Stops the registry `server`.
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(server), do: GenServer.stop(server)

  @doc """
  Stores the interval `{start, finish}` and returns `{:ok, id}`.

  `id` is a unique integer handle for the stored interval. Identical intervals
  may be inserted repeatedly and each receives its own id.

  Ids are handed out by the server in insertion order: the first successful
  insert returns `1`, and every later insert returns the previous id plus one.
  Ids are never reused, even after the interval they name is removed.
  """
  @spec insert(GenServer.server(), interval()) :: {:ok, pos_integer()}
  def insert(server, {s, f}) when is_integer(s) and is_integer(f) and s <= f do
    GenServer.call(server, {:insert, s, f})
  end

  @doc """
  Removes the interval previously stored under `id`.

  Returns `:ok` when the id was present, or `{:error, :not_found}` when it was
  not (or was already removed).
  """
  @spec remove(GenServer.server(), integer()) :: :ok | {:error, :not_found}
  def remove(server, id) when is_integer(id), do: GenServer.call(server, {:remove, id})

  @doc """
  Returns the sorted list of stored intervals that overlap `{start, finish}`.

  Two intervals overlap when they share at least one point.
  """
  @spec overlapping(GenServer.server(), interval()) :: [interval()]
  def overlapping(server, {s, f}) when is_integer(s) and is_integer(f) and s <= f do
    GenServer.call(server, {:overlapping, s, f})
  end

  @doc """
  Returns the sorted list of stored intervals that contain `point`.
  """
  @spec enclosing(GenServer.server(), integer()) :: [interval()]
  def enclosing(server, point) when is_integer(point) do
    GenServer.call(server, {:enclosing, point})
  end

  @doc """
  Returns the number of stored intervals that contain `point`.
  """
  @spec stab_count(GenServer.server(), integer()) :: non_neg_integer()
  def stab_count(server, point) when is_integer(point) do
    GenServer.call(server, {:stab_count, point})
  end

  @doc """
  Returns the number of intervals currently stored.
  """
  @spec size(GenServer.server()) :: non_neg_integer()
  def size(server), do: GenServer.call(server, :size)

  # -------------------------------------------------------------------------
  # Server callbacks
  # -------------------------------------------------------------------------

  @impl true
  def init(:ok), do: {:ok, %{tree: nil, next_id: 1, entries: %{}}}

  @impl true
  def handle_call({:insert, s, f}, _from, state) do
    id = state.next_id
    tree = t_insert(state.tree, s, f, id)

    new_state = %{
      state
      | tree: tree,
        next_id: id + 1,
        entries: Map.put(state.entries, id, {s, f})
    }

    {:reply, {:ok, id}, new_state}
  end

  def handle_call({:remove, id}, _from, state) do
    case Map.fetch(state.entries, id) do
      {:ok, {s, f}} ->
        tree = t_delete(state.tree, s, f, id)
        {:reply, :ok, %{state | tree: tree, entries: Map.delete(state.entries, id)}}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:overlapping, qs, qf}, _from, state) do
    {:reply, Enum.sort(t_overlapping(state.tree, qs, qf, [])), state}
  end

  def handle_call({:enclosing, point}, _from, state) do
    {:reply, Enum.sort(t_enclosing(state.tree, point, [])), state}
  end

  def handle_call({:stab_count, point}, _from, state) do
    {:reply, t_stab_count(state.tree, point, 0), state}
  end

  def handle_call(:size, _from, state) do
    {:reply, map_size(state.entries), state}
  end

  # -------------------------------------------------------------------------
  # Internal augmented AVL tree, keyed by {s, f, id}
  # -------------------------------------------------------------------------

  defp t_height(nil), do: 0
  defp t_height(%{height: h}), do: h

  defp t_node(s, f, id, left, right) do
    h = 1 + max(t_height(left), t_height(right))
    mf = f |> t_max_child(left) |> t_max_child(right)
    %{s: s, f: f, id: id, max_finish: mf, height: h, left: left, right: right}
  end

  defp t_max_child(acc, nil), do: acc
  defp t_max_child(acc, %{max_finish: mf}), do: max(acc, mf)

  defp t_key(%{s: s, f: f, id: id}), do: {s, f, id}

  defp t_bf(nil), do: 0
  defp t_bf(%{left: l, right: r}), do: t_height(l) - t_height(r)

  defp t_rotate_right(%{left: %{} = y} = x) do
    t_node(y.s, y.f, y.id, y.left, t_node(x.s, x.f, x.id, y.right, x.right))
  end

  defp t_rotate_left(%{right: %{} = y} = x) do
    t_node(y.s, y.f, y.id, t_node(x.s, x.f, x.id, x.left, y.left), y.right)
  end

  defp t_rebalance(node) do
    bf = t_bf(node)

    cond do
      bf > 1 ->
        node =
          if t_bf(node.left) < 0 do
            t_node(node.s, node.f, node.id, t_rotate_left(node.left), node.right)
          else
            node
          end

        t_rotate_right(node)

      bf < -1 ->
        node =
          if t_bf(node.right) > 0 do
            t_node(node.s, node.f, node.id, node.left, t_rotate_right(node.right))
          else
            node
          end

        t_rotate_left(node)

      true ->
        node
    end
  end

  defp t_insert(nil, s, f, id), do: t_node(s, f, id, nil, nil)

  defp t_insert(node, s, f, id) do
    updated =
      if {s, f, id} < t_key(node) do
        t_node(node.s, node.f, node.id, t_insert(node.left, s, f, id), node.right)
      else
        t_node(node.s, node.f, node.id, node.left, t_insert(node.right, s, f, id))
      end

    t_rebalance(updated)
  end

  defp t_delete(nil, _s, _f, _id), do: nil

  defp t_delete(node, s, f, id) do
    key = {s, f, id}
    nkey = t_key(node)

    cond do
      key < nkey ->
        t_rebalance(t_node(node.s, node.f, node.id, t_delete(node.left, s, f, id), node.right))

      key > nkey ->
        t_rebalance(t_node(node.s, node.f, node.id, node.left, t_delete(node.right, s, f, id)))

      true ->
        t_delete_here(node)
    end
  end

  defp t_delete_here(%{left: nil, right: r}), do: r
  defp t_delete_here(%{left: l, right: nil}), do: l

  defp t_delete_here(%{left: l, right: r}) do
    succ = t_min(r)
    nr = t_delete(r, succ.s, succ.f, succ.id)
    t_rebalance(t_node(succ.s, succ.f, succ.id, l, nr))
  end

  defp t_min(%{left: nil} = node), do: node
  defp t_min(%{left: l}), do: t_min(l)

  defp t_overlapping(nil, _qs, _qf, acc), do: acc
  defp t_overlapping(%{max_finish: mf}, qs, _qf, acc) when mf < qs, do: acc

  defp t_overlapping(%{s: s, f: f, left: l, right: r}, qs, qf, acc) do
    acc = if s <= qf and f >= qs, do: [{s, f} | acc], else: acc
    acc = t_overlapping(l, qs, qf, acc)

    if s <= qf, do: t_overlapping(r, qs, qf, acc), else: acc
  end

  defp t_enclosing(nil, _point, acc), do: acc
  defp t_enclosing(%{max_finish: mf}, point, acc) when mf < point, do: acc

  defp t_enclosing(%{s: s, f: f, left: l, right: r}, point, acc) do
    acc = if s <= point and point <= f, do: [{s, f} | acc], else: acc
    acc = t_enclosing(l, point, acc)

    if s <= point, do: t_enclosing(r, point, acc), else: acc
  end

  defp t_stab_count(nil, _point, acc), do: acc
  defp t_stab_count(%{max_finish: mf}, point, acc) when mf < point, do: acc

  defp t_stab_count(%{s: s, f: f, left: l, right: r}, point, acc) do
    acc = if s <= point and point <= f, do: acc + 1, else: acc
    acc = t_stab_count(l, point, acc)

    if s <= point, do: t_stab_count(r, point, acc), else: acc
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule IntervalRegistryTest do
  use ExUnit.Case, async: false

  # Large enough that an unbalanced (linear-depth) tree needs quadratic work.
  @big 10_000

  setup do
    {:ok, pid} = IntervalRegistry.start_link()

    on_exit(fn ->
      if Process.alive?(pid), do: IntervalRegistry.stop(pid)
    end)

    %{server: pid}
  end

  # ---------------------------------------------------------------
  # Empty registry
  # ---------------------------------------------------------------

  test "empty registry queries", %{server: s} do
    assert [] = IntervalRegistry.overlapping(s, {1, 10})
    assert [] = IntervalRegistry.enclosing(s, 5)
    assert IntervalRegistry.stab_count(s, 5) == 0
    assert IntervalRegistry.size(s) == 0
  end

  # ---------------------------------------------------------------
  # Insert returns ids; queries reflect stored intervals
  # ---------------------------------------------------------------

  test "insert returns unique ids", %{server: s} do
    {:ok, id1} = IntervalRegistry.insert(s, {1, 5})
    {:ok, id2} = IntervalRegistry.insert(s, {1, 5})
    {:ok, id3} = IntervalRegistry.insert(s, {10, 20})

    assert id1 != id2
    assert id2 != id3
    assert IntervalRegistry.size(s) == 3
  end

  test "ids start at 1 and advance by exactly one per insert", %{server: s} do
    assert {:ok, 1} = IntervalRegistry.insert(s, {1, 2})
    assert {:ok, 2} = IntervalRegistry.insert(s, {1, 2})
    assert {:ok, 3} = IntervalRegistry.insert(s, {5, 9})

    # Removing an id does not rewind or reuse the counter.
    assert :ok = IntervalRegistry.remove(s, 2)
    assert {:ok, 4} = IntervalRegistry.insert(s, {0, 0})

    assert :ok = IntervalRegistry.remove(s, 1)
    assert :ok = IntervalRegistry.remove(s, 3)
    assert :ok = IntervalRegistry.remove(s, 4)
    assert IntervalRegistry.size(s) == 0

    assert {:ok, 5} = IntervalRegistry.insert(s, {2, 2})
    assert [{2, 2}] = IntervalRegistry.enclosing(s, 2)
  end

  test "a fresh server restarts the id sequence at 1", %{server: s} do
    assert {:ok, 1} = IntervalRegistry.insert(s, {3, 4})
    assert {:ok, 2} = IntervalRegistry.insert(s, {3, 4})

    {:ok, other} = IntervalRegistry.start_link()
    assert {:ok, 1} = IntervalRegistry.insert(other, {7, 8})
    assert {:ok, 2} = IntervalRegistry.insert(other, {7, 8})
    assert :ok = IntervalRegistry.stop(other)
  end

  test "overlapping returns sorted matches", %{server: s} do
    {:ok, _} = IntervalRegistry.insert(s, {1, 5})
    {:ok, _} = IntervalRegistry.insert(s, {3, 8})
    {:ok, _} = IntervalRegistry.insert(s, {10, 15})

    assert [{1, 5}, {3, 8}] = IntervalRegistry.overlapping(s, {4, 6})
    assert [{3, 8}] = IntervalRegistry.overlapping(s, {8, 9})
    assert [] = IntervalRegistry.overlapping(s, {20, 25})
  end

  test "touching intervals overlap", %{server: s} do
    {:ok, _} = IntervalRegistry.insert(s, {1, 5})
    {:ok, _} = IntervalRegistry.insert(s, {5, 10})
    assert [{1, 5}, {5, 10}] = IntervalRegistry.overlapping(s, {5, 5})
  end

  test "query boundaries are inclusive at both ends", %{server: s} do
    for iv <- [{1, 5}, {5, 6}, {6, 10}, {2, 3}, {10, 12}] do
      {:ok, _} = IntervalRegistry.insert(s, iv)
    end

    assert IntervalRegistry.overlapping(s, {5, 5}) == [{1, 5}, {5, 6}]
    assert IntervalRegistry.overlapping(s, {6, 6}) == [{5, 6}, {6, 10}]
    assert IntervalRegistry.overlapping(s, {3, 5}) == [{1, 5}, {2, 3}, {5, 6}]
    assert IntervalRegistry.overlapping(s, {12, 99}) == [{10, 12}]
    assert IntervalRegistry.overlapping(s, {0, 1}) == [{1, 5}]
    assert IntervalRegistry.stab_count(s, 10) == 2
    assert IntervalRegistry.stab_count(s, 5) == 2
  end

  test "enclosing and stab_count", %{server: s} do
    {:ok, _} = IntervalRegistry.insert(s, {1, 10})
    {:ok, _} = IntervalRegistry.insert(s, {3, 7})
    {:ok, _} = IntervalRegistry.insert(s, {6, 15})
    {:ok, _} = IntervalRegistry.insert(s, {20, 30})

    assert [{1, 10}, {3, 7}, {6, 15}] = IntervalRegistry.enclosing(s, 6)
    assert IntervalRegistry.stab_count(s, 6) == 3
    assert IntervalRegistry.stab_count(s, 25) == 1
    assert IntervalRegistry.stab_count(s, 100) == 0
  end

  test "degenerate interval", %{server: s} do
    {:ok, _} = IntervalRegistry.insert(s, {4, 4})
    assert [{4, 4}] = IntervalRegistry.enclosing(s, 4)
    assert [] = IntervalRegistry.enclosing(s, 5)
    assert IntervalRegistry.stab_count(s, 4) == 1
  end

  # ---------------------------------------------------------------
  # remove semantics
  # ---------------------------------------------------------------

  test "remove deletes exactly the stored interval by id", %{server: s} do
    {:ok, id_a} = IntervalRegistry.insert(s, {3, 8})
    {:ok, _id_b} = IntervalRegistry.insert(s, {3, 8})

    assert IntervalRegistry.size(s) == 2
    assert :ok = IntervalRegistry.remove(s, id_a)
    assert IntervalRegistry.size(s) == 1
    # one copy remains
    assert [{3, 8}] = IntervalRegistry.overlapping(s, {1, 10})
  end

  test "remove of unknown id returns not_found", %{server: s} do
    assert {:error, :not_found} = IntervalRegistry.remove(s, 9999)
    {:ok, id} = IntervalRegistry.insert(s, {1, 2})
    assert :ok = IntervalRegistry.remove(s, id)
    # removing again fails
    assert {:error, :not_found} = IntervalRegistry.remove(s, id)
  end

  test "remove updates overlap results", %{server: s} do
    {:ok, _} = IntervalRegistry.insert(s, {1, 5})
    {:ok, mid} = IntervalRegistry.insert(s, {3, 8})
    {:ok, _} = IntervalRegistry.insert(s, {10, 15})

    assert :ok = IntervalRegistry.remove(s, mid)
    assert [{1, 5}] = IntervalRegistry.overlapping(s, {4, 6})
  end

  # ---------------------------------------------------------------
  # stop/1 — actually terminates the running server
  # ---------------------------------------------------------------

  test "stop terminates the running server", %{server: s} do
    assert Process.alive?(s)
    ref = Process.monitor(s)

    assert :ok = IntervalRegistry.stop(s)

    assert_receive {:DOWN, ^ref, :process, ^s, _reason}, 1_000
    refute Process.alive?(s)
  end

  test "stop shuts down an independently started server", %{server: _s} do
    {:ok, other} = IntervalRegistry.start_link()
    {:ok, _} = IntervalRegistry.insert(other, {1, 2})
    assert IntervalRegistry.size(other) == 1

    assert Process.alive?(other)
    assert :ok = IntervalRegistry.stop(other)
    refute Process.alive?(other)

    # A stopped server no longer answers calls.
    assert catch_exit(IntervalRegistry.size(other))
  end

  # ---------------------------------------------------------------
  # Concurrency — many client processes mutate the shared server
  # ---------------------------------------------------------------

  test "concurrent inserts are all recorded consistently", %{server: s} do
    1..200
    |> Task.async_stream(fn i -> IntervalRegistry.insert(s, {i, i + 5}) end,
      max_concurrency: 20,
      ordered: false
    )
    |> Enum.to_list()

    assert IntervalRegistry.size(s) == 200

    # Intervals {i, i+5} cover point 10 iff i <= 10 <= i+5, i.e. i in 5..10 → 6 of them.
    assert IntervalRegistry.stab_count(s, 10) == 6
  end

  test "concurrent inserts and removes leave a consistent count", %{server: s} do
    # TODO
  end

  test "start_link registers under a :name and the api works through that name" do
    name = :interval_registry_promise_named
    {:ok, pid} = IntervalRegistry.start_link(name: name)
    assert Process.whereis(name) == pid

    {:ok, id} = IntervalRegistry.insert(name, {2, 6})
    assert IntervalRegistry.size(name) == 1
    assert [{2, 6}] = IntervalRegistry.overlapping(name, {6, 9})
    assert IntervalRegistry.stab_count(name, 4) == 1
    assert :ok = IntervalRegistry.remove(name, id)
    assert IntervalRegistry.size(name) == 0

    ref = Process.monitor(pid)
    assert :ok = IntervalRegistry.stop(name)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000
  end

  test "overlapping matches a brute-force scan over a large mixed tree", %{server: s} do
    intervals =
      for i <- 1..120 do
        start = rem(i * 37, 100)
        {start, start + rem(i * 13, 20)}
      end

    Enum.each(intervals, fn iv -> {:ok, _} = IntervalRegistry.insert(s, iv) end)
    assert IntervalRegistry.size(s) == 120

    queries = [{0, 0}, {5, 5}, {40, 50}, {-10, 3}, {99, 200}, {0, 200}, {200, 300}]

    for {qs, qf} = q <- queries do
      expected =
        intervals
        |> Enum.filter(fn {a, b} -> a <= qf and b >= qs end)
        |> Enum.sort()

      assert IntervalRegistry.overlapping(s, q) == expected
    end
  end

  test "enclosing sorts results and includes both endpoints of each interval", %{server: s} do
    for iv <- [{9, 12}, {1, 5}, {5, 5}, {-3, 1}, {2, 9}] do
      {:ok, _} = IntervalRegistry.insert(s, iv)
    end

    assert IntervalRegistry.enclosing(s, 1) == [{-3, 1}, {1, 5}]
    assert IntervalRegistry.enclosing(s, 5) == [{1, 5}, {2, 9}, {5, 5}]
    assert IntervalRegistry.enclosing(s, 9) == [{2, 9}, {9, 12}]
    assert IntervalRegistry.enclosing(s, 12) == [{9, 12}]
    assert IntervalRegistry.enclosing(s, 13) == []
  end

  test "queries match the surviving set after concurrent inserts and removes", %{server: s} do
    pairs =
      1..150
      |> Task.async_stream(fn i -> {i, IntervalRegistry.insert(s, {i, i + 10})} end,
        max_concurrency: 16,
        ordered: false
      )
      |> Enum.map(fn {:ok, {i, {:ok, id}}} -> {i, id} end)

    {kept, dropped} = Enum.split_with(pairs, fn {i, _id} -> rem(i, 3) == 0 end)

    dropped
    |> Task.async_stream(fn {_i, id} -> :ok = IntervalRegistry.remove(s, id) end,
      max_concurrency: 16,
      ordered: false
    )
    |> Enum.to_list()

    expected = kept |> Enum.map(fn {i, _id} -> {i, i + 10} end) |> Enum.sort()
    stabbed = Enum.filter(expected, fn {a, b} -> a <= 60 and 60 <= b end)

    assert IntervalRegistry.size(s) == length(kept)
    assert IntervalRegistry.overlapping(s, {1, 200}) == expected
    assert IntervalRegistry.enclosing(s, 60) == stabbed
    assert IntervalRegistry.stab_count(s, 60) == length(stabbed)
  end

  test "ids are unique across concurrent clients and not reused after removal", %{server: s} do
    ids =
      1..100
      |> Task.async_stream(fn i -> IntervalRegistry.insert(s, {i, i}) end,
        max_concurrency: 16,
        ordered: false
      )
      |> Enum.map(fn {:ok, {:ok, id}} -> id end)

    assert Enum.all?(ids, &is_integer/1)
    assert length(Enum.uniq(ids)) == 100

    Enum.each(ids, fn id -> assert :ok = IntervalRegistry.remove(s, id) end)
    assert IntervalRegistry.size(s) == 0

    {:ok, fresh} = IntervalRegistry.insert(s, {1, 1})
    refute fresh in ids
  end

  test "insert rejects a reversed interval instead of storing it", %{server: s} do
    assert_raise FunctionClauseError, fn -> IntervalRegistry.insert(s, {7, 3}) end
    assert IntervalRegistry.size(s) == 0

    {:ok, _} = IntervalRegistry.insert(s, {3, 7})
    assert IntervalRegistry.size(s) == 1
    assert [{3, 7}] = IntervalRegistry.overlapping(s, {7, 7})
  end

  # ---------------------------------------------------------------
  # Self-balancing — sorted insertion orders are the worst case for an
  # unbalanced BST (depth n, so n inserts cost O(n^2)). A tree that keeps
  # its height logarithmic finishes these in well under a second; one that
  # never rebalances needs minutes and blows the deadline below.
  # ---------------------------------------------------------------

  test "ascending inserts stay logarithmic and query correctly" do
    {:ok, srv} = IntervalRegistry.start_link()

    task =
      Task.async(fn ->
        Enum.each(1..@big, fn i -> {:ok, _} = IntervalRegistry.insert(srv, {i, i + 1}) end)
        :inserted
      end)

    assert {:ok, :inserted} = Task.yield(task, 20_000) || Task.shutdown(task, :brutal_kill)

    assert IntervalRegistry.size(srv) == @big
    assert IntervalRegistry.stab_count(srv, 5_000) == 2
    assert IntervalRegistry.enclosing(srv, 5_000) == [{4_999, 5_000}, {5_000, 5_001}]
    assert IntervalRegistry.overlapping(srv, {1, 1}) == [{1, 2}]
    assert IntervalRegistry.enclosing(srv, @big + 1) == [{@big, @big + 1}]
    assert IntervalRegistry.stab_count(srv, @big + 2) == 0

    assert :ok = IntervalRegistry.stop(srv)
  end

  test "descending inserts stay logarithmic and query correctly" do
    {:ok, srv} = IntervalRegistry.start_link()

    task =
      Task.async(fn ->
        Enum.each(@big..1//-1, fn i -> {:ok, _} = IntervalRegistry.insert(srv, {i, i}) end)
        :inserted
      end)

    assert {:ok, :inserted} = Task.yield(task, 20_000) || Task.shutdown(task, :brutal_kill)

    assert IntervalRegistry.size(srv) == @big
    assert IntervalRegistry.stab_count(srv, 7_777) == 1
    assert IntervalRegistry.enclosing(srv, 1) == [{1, 1}]
    assert IntervalRegistry.enclosing(srv, 0) == []
    assert IntervalRegistry.overlapping(srv, {3, 6}) == [{3, 3}, {4, 4}, {5, 5}, {6, 6}]

    assert :ok = IntervalRegistry.stop(srv)
  end

  test "interleaved inserts and removes keep the tree balanced and consistent" do
    {:ok, srv} = IntervalRegistry.start_link()
    half = div(@big, 2)

    task =
      Task.async(fn ->
        ids =
          Enum.map(1..@big, fn i ->
            {:ok, id} = IntervalRegistry.insert(srv, {i, i + 3})
            {i, id}
          end)

        Enum.each(ids, fn {i, id} ->
          if i > half, do: :ok = IntervalRegistry.remove(srv, id)
        end)

        :done
      end)

    assert {:ok, :done} = Task.yield(task, 30_000) || Task.shutdown(task, :brutal_kill)

    assert IntervalRegistry.size(srv) == half
    assert IntervalRegistry.overlapping(srv, {half + 4, @big}) == []

    assert IntervalRegistry.enclosing(srv, half) == [
             {half - 3, half},
             {half - 2, half + 1},
             {half - 1, half + 2},
             {half, half + 3}
           ]

    assert IntervalRegistry.stab_count(srv, half) == 4

    assert :ok = IntervalRegistry.stop(srv)
  end
end
```
