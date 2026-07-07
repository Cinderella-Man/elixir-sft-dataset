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
    {:ok, pid} = CacheLayer.start_link([])

    # Touch two tables so both get lazily created and registered.
    assert {:ok, :v1} = CacheLayer.fetch(pid, :cleanup_a, "k", fn -> :v1 end)
    assert {:ok, :v2} = CacheLayer.fetch(pid, :cleanup_b, "k", fn -> :v2 end)

    # The fast read-path registrations exist while the server is alive.
    tid_a = :persistent_term.get({CacheLayer, pid, :cleanup_a})
    tid_b = :persistent_term.get({CacheLayer, pid, :cleanup_b})
    assert :ets.info(tid_a) != :undefined
    assert :ets.info(tid_b) != :undefined
    assert :ets.lookup(tid_a, "k") == [{"k", :v1}]

    # A clean stop must run terminate/2, which erases every registration.
    :ok = GenServer.stop(pid)

    assert :persistent_term.get({CacheLayer, pid, :cleanup_a}, :gone) == :gone
    assert :persistent_term.get({CacheLayer, pid, :cleanup_b}, :gone) == :gone
  end

  test "terminate/2 runs during a supervised shutdown without crashing" do
    {:ok, sup} = Supervisor.start_link([{CacheLayer, []}], strategy: :one_for_one)
    [{_id, pid, _type, _mods}] = Supervisor.which_children(sup)

    assert {:ok, :v} = CacheLayer.fetch(pid, :sup_tbl, "k", fn -> :v end)
    assert :persistent_term.get({CacheLayer, pid, :sup_tbl}) |> :ets.info() != :undefined

    ref = Process.monitor(pid)
    :ok = Supervisor.stop(sup)

    # The child must have exited normally (a raising terminate/2 would surface
    # here as an abnormal exit reason), and its registration must be gone.
    assert_receive {:DOWN, ^ref, :process, ^pid, reason}
    assert reason in [:normal, :shutdown]
    assert :persistent_term.get({CacheLayer, pid, :sup_tbl}, :gone) == :gone
  end
end
