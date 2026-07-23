# Implement to green

Treat the ExUnit suite below as the full requirements document. Write the
code under test so the whole suite passes. Dependencies: only what the
tests already use (the standard library and OTP otherwise). Style:
`@moduledoc`, `@doc` + `@spec` on the public API, warning-free compile.

## The test suite

```elixir
defmodule CacheLayerWriteThroughTest do
  use ExUnit.Case, async: false

  # A mock backing store that records load/write/delete calls and can be
  # toggled to fail its write/delete operations.
  defmodule Store do
    use Agent

    def start_link(_) do
      Agent.start_link(fn -> %{loads: 0, writes: 0, deletes: 0, fail: false} end,
        name: __MODULE__
      )
    end

    def loaded(value) do
      Agent.update(__MODULE__, fn s -> %{s | loads: s.loads + 1} end)
      value
    end

    def write do
      Agent.get_and_update(__MODULE__, fn s ->
        resp = if s.fail, do: {:error, :store_down}, else: :ok
        {resp, %{s | writes: s.writes + 1}}
      end)
    end

    def delete do
      Agent.get_and_update(__MODULE__, fn s ->
        resp = if s.fail, do: {:error, :store_down}, else: :ok
        {resp, %{s | deletes: s.deletes + 1}}
      end)
    end

    def set_fail(bool), do: Agent.update(__MODULE__, fn s -> %{s | fail: bool} end)
    def counts, do: Agent.get(__MODULE__, & &1)
  end

  setup do
    start_supervised!({Store, :ok})
    cl = start_supervised!({CacheLayer, []})
    %{cl: cl}
  end

  # -------------------------------------------------------
  # Read-through
  # -------------------------------------------------------

  test "fetch loads on a miss and caches for later hits", %{cl: cl} do
    loader = fn -> Store.loaded(:v1) end

    assert {:ok, :v1} = CacheLayer.fetch(cl, :users, "u:1", loader)
    assert {:ok, :v1} = CacheLayer.fetch(cl, :users, "u:1", loader)
    assert Store.counts().loads == 1
  end

  test "concurrent misses call the loader at most once", %{cl: cl} do
    loader = fn ->
      Process.sleep(20)
      Store.loaded(:v)
    end

    results =
      for _ <- 1..25 do
        Task.async(fn -> CacheLayer.fetch(cl, :users, "hot", loader) end)
      end
      |> Enum.map(&Task.await/1)

    assert Enum.all?(results, &(&1 == {:ok, :v}))
    assert Store.counts().loads == 1
  end

  # -------------------------------------------------------
  # Write-through
  # -------------------------------------------------------

  test "put writes through to the store then updates the cache", %{cl: cl} do
    assert {:ok, :new} = CacheLayer.put(cl, :users, "u:1", :new, &Store.write/0)
    assert Store.counts().writes == 1

    # Subsequent fetch is served from cache — loader never runs.
    assert {:ok, :new} = CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:from_db) end)
    assert Store.counts().loads == 0
  end

  test "put overwrites an existing cached value", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:old) end)
    assert {:ok, :updated} = CacheLayer.put(cl, :users, "u:1", :updated, &Store.write/0)

    assert {:ok, :updated} = CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:x) end)
    # Only the original load happened; the second fetch was a cache hit.
    assert Store.counts().loads == 1
  end

  test "a failed write leaves the previously cached value intact", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:v1) end)
    Store.set_fail(true)

    assert {:error, :store_down} = CacheLayer.put(cl, :users, "u:1", :v2, &Store.write/0)
    assert Store.counts().writes == 1

    # Cache untouched — still the old value, no reload.
    assert {:ok, :v1} = CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:x) end)
    assert Store.counts().loads == 1
  end

  # -------------------------------------------------------
  # Delete-through
  # -------------------------------------------------------

  test "delete removes from the store then the cache", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:v1) end)

    assert :ok = CacheLayer.delete(cl, :users, "u:1", &Store.delete/0)
    assert Store.counts().deletes == 1

    # Cache miss now -> reload.
    assert {:ok, :v2} = CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:v2) end)
    assert Store.counts().loads == 2
  end

  test "a failed delete leaves the cached value intact", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:v1) end)
    Store.set_fail(true)

    assert {:error, :store_down} = CacheLayer.delete(cl, :users, "u:1", &Store.delete/0)
    assert Store.counts().deletes == 1

    # Still cached — no reload.
    assert {:ok, :v1} = CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:x) end)
    assert Store.counts().loads == 1
  end

  # -------------------------------------------------------
  # Cache-only invalidation (store untouched)
  # -------------------------------------------------------

  test "invalidate evicts from the cache without touching the store", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:v1) end)

    assert :ok = CacheLayer.invalidate(cl, :users, "u:1")
    assert Store.counts().deletes == 0

    # Evicted -> reload.
    assert {:ok, :v2} = CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:v2) end)
    assert Store.counts().loads == 2
  end

  test "invalidate_all clears the table without touching the store", %{cl: cl} do
    for i <- 1..5 do
      CacheLayer.fetch(cl, :users, "u:#{i}", fn -> Store.loaded(i) end)
    end

    assert Store.counts().loads == 5
    assert :ok = CacheLayer.invalidate_all(cl, :users)
    assert Store.counts().deletes == 0

    for i <- 1..5 do
      CacheLayer.fetch(cl, :users, "u:#{i}", fn -> Store.loaded(i) end)
    end

    assert Store.counts().loads == 10
  end

  test "invalidate on a non-existent key returns :ok", %{cl: cl} do
    assert :ok = CacheLayer.invalidate(cl, :users, "nope")
  end

  test "invalidate_all on an unused table returns :ok", %{cl: cl} do
    assert :ok = CacheLayer.invalidate_all(cl, :never_used)
  end

  # -------------------------------------------------------
  # Table independence
  # -------------------------------------------------------

  test "put on one table does not affect another", %{cl: cl} do
    CacheLayer.put(cl, :users, "id:1", :u, &Store.write/0)
    CacheLayer.put(cl, :posts, "id:1", :p, &Store.write/0)

    assert {:ok, :u} = CacheLayer.fetch(cl, :users, "id:1", fn -> Store.loaded(:x) end)
    assert {:ok, :p} = CacheLayer.fetch(cl, :posts, "id:1", fn -> Store.loaded(:x) end)
    assert Store.counts().loads == 0
  end

  # -------------------------------------------------------
  # Termination / cleanup (exercises terminate/2)
  # -------------------------------------------------------

  test "stopping the server cleans up its persistent_term registrations" do
    # Snapshot the registry first so the test observes exactly the entries this
    # instance creates, without assuming anything about how they are keyed.
    before_keys = MapSet.new(:persistent_term.get(), fn {key, _} -> key end)

    {:ok, pid} = CacheLayer.start_link([])

    # Touch two tables so both get lazily created and registered.
    assert {:ok, :v1} = CacheLayer.fetch(pid, :cleanup_a, "k", fn -> :v1 end)
    assert {:ok, :v2} = CacheLayer.fetch(pid, :cleanup_b, "k", fn -> :v2 end)

    # While the server is alive both keys are cache hits: a loader that raises
    # proves the values are served from the cache, not reloaded.
    boom = fn -> raise "loader must not run on a cache hit" end
    assert {:ok, :v1} = CacheLayer.fetch(pid, :cleanup_a, "k", boom)
    assert {:ok, :v2} = CacheLayer.fetch(pid, :cleanup_b, "k", boom)

    alive_keys = MapSet.new(:persistent_term.get(), fn {key, _} -> key end)
    created = MapSet.difference(alive_keys, before_keys)

    # A clean stop must run terminate/2, which erases every registration the
    # server made, whatever naming scheme it chose.
    :ok = GenServer.stop(pid)

    remaining = MapSet.new(:persistent_term.get(), fn {key, _} -> key end)
    assert MapSet.disjoint?(created, remaining)
  end

  test "terminate/2 runs during a supervised shutdown without crashing" do
    before_keys = MapSet.new(:persistent_term.get(), fn {key, _} -> key end)

    {:ok, sup} = Supervisor.start_link([{CacheLayer, []}], strategy: :one_for_one)
    [{_id, pid, _type, _mods}] = Supervisor.which_children(sup)

    assert {:ok, :v} = CacheLayer.fetch(pid, :sup_tbl, "k", fn -> :v end)
    # A repeat fetch is a cache hit; the raising loader proves it never runs.
    boom = fn -> raise "loader must not run on a cache hit" end
    assert {:ok, :v} = CacheLayer.fetch(pid, :sup_tbl, "k", boom)

    alive_keys = MapSet.new(:persistent_term.get(), fn {key, _} -> key end)
    created = MapSet.difference(alive_keys, before_keys)

    ref = Process.monitor(pid)
    :ok = Supervisor.stop(sup)

    # The child must have exited normally (a raising terminate/2 would surface
    # here as an abnormal exit reason), and its registrations must be gone.
    assert_receive {:DOWN, ^ref, :process, ^pid, reason}
    assert reason in [:normal, :shutdown]

    remaining = MapSet.new(:persistent_term.get(), fn {key, _} -> key end)
    assert MapSet.disjoint?(created, remaining)
  end

  test "cache hits are served from ETS while the server is blocked in a loader", %{cl: cl} do
    assert {:ok, :warm} = CacheLayer.fetch(cl, :users, "warm", fn -> Store.loaded(:warm) end)

    test_pid = self()
    gate = spawn(fn -> Process.sleep(:infinity) end)

    slow_loader = fn ->
      ref = Process.monitor(gate)
      send(test_pid, :loader_running)

      receive do
        {:DOWN, ^ref, :process, _, _} -> :ok
      end

      Store.loaded(:slow)
    end

    blocked = Task.async(fn -> CacheLayer.fetch(cl, :users, "slow", slow_loader) end)
    assert_receive :loader_running, 1_000

    boom = fn -> raise "a cache hit must not call the loader" end
    reader = Task.async(fn -> CacheLayer.fetch(cl, :users, "warm", boom) end)

    assert {:ok, {:ok, :warm}} = Task.yield(reader, 500) || Task.shutdown(reader, :brutal_kill)

    Process.exit(gate, :kill)
    assert {:ok, :slow} = Task.await(blocked, 1_000)
  end

  test "a :name registered server serves fetch, put and invalidate through the name" do
    start_supervised!(Supervisor.child_spec({CacheLayer, [name: :cl_named]}, id: :cl_named))

    assert {:ok, :v1} = CacheLayer.fetch(:cl_named, :users, "u:1", fn -> Store.loaded(:v1) end)

    boom = fn -> raise "a cache hit must not call the loader" end
    assert {:ok, :v1} = CacheLayer.fetch(:cl_named, :users, "u:1", boom)

    assert {:ok, :v2} = CacheLayer.put(:cl_named, :users, "u:1", :v2, &Store.write/0)
    assert {:ok, :v2} = CacheLayer.fetch(:cl_named, :users, "u:1", boom)

    assert :ok = CacheLayer.invalidate(:cl_named, :users, "u:1")
    assert {:ok, :v3} = CacheLayer.fetch(:cl_named, :users, "u:1", fn -> Store.loaded(:v3) end)
    assert Store.counts().loads == 2
  end

  test "put accepts an {:ok, term} writer result and caches the value", %{cl: cl} do
    writer = fn -> {:ok, :store_receipt} end

    assert {:ok, :v2} = CacheLayer.put(cl, :users, "u:1", :v2, writer)

    boom = fn -> raise "a cache hit must not call the loader" end
    assert {:ok, :v2} = CacheLayer.fetch(cl, :users, "u:1", boom)
    assert Store.counts().loads == 0
  end

  test "delete accepts an {:ok, term} deleter result and evicts the entry", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:v1) end)

    assert :ok = CacheLayer.delete(cl, :users, "u:1", fn -> {:ok, :deleted_1_row} end)

    assert {:ok, :v2} = CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:v2) end)
    assert Store.counts().loads == 2
  end

  test "a failed put does not populate the cache for a previously uncached key", %{cl: cl} do
    Store.set_fail(true)

    assert {:error, :store_down} = CacheLayer.put(cl, :users, "u:9", :v2, &Store.write/0)

    Store.set_fail(false)

    assert {:ok, :from_store} =
             CacheLayer.fetch(cl, :users, "u:9", fn -> Store.loaded(:from_store) end)

    assert Store.counts().loads == 1
    assert Store.counts().writes == 1
  end

  test "invalidate_all clears only the named table and leaves other tables cached", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "id:1", fn -> Store.loaded(:u) end)
    CacheLayer.fetch(cl, :posts, "id:1", fn -> Store.loaded(:p) end)

    assert :ok = CacheLayer.invalidate_all(cl, :users)

    boom = fn -> raise "a cache hit must not call the loader" end
    assert {:ok, :p} = CacheLayer.fetch(cl, :posts, "id:1", boom)
    assert {:ok, :u2} = CacheLayer.fetch(cl, :users, "id:1", fn -> Store.loaded(:u2) end)
    assert Store.counts().loads == 3
  end
end
```

Deliverable: the module(s) alone in a single file — not the tests.
