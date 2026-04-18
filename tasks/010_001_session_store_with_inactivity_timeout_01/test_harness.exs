defmodule SessionStoreTest do
  use ExUnit.Case, async: false

  # --- Fake clock for deterministic testing ---

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
    def set(ms), do: Agent.update(__MODULE__, fn _ -> ms end)
  end

  setup do
    start_supervised!({Clock, 0})

    {:ok, pid} =
      SessionStore.start_link(
        clock: &Clock.now/0,
        timeout_ms: 1_000,
        cleanup_interval_ms: :infinity
      )

    %{store: pid}
  end

  # -------------------------------------------------------
  # Basic create / get / destroy
  # -------------------------------------------------------

  test "create returns a unique session id", %{store: store} do
    assert {:ok, id1} = SessionStore.create(store, %{user: "alice"})
    assert {:ok, id2} = SessionStore.create(store, %{user: "bob"})

    assert is_binary(id1)
    assert is_binary(id2)
    assert id1 != id2
  end

  test "get retrieves created session data", %{store: store} do
    {:ok, id} = SessionStore.create(store, %{user: "alice", role: :admin})

    assert {:ok, %{user: "alice", role: :admin}} = SessionStore.get(store, id)
  end

  test "get returns error for unknown session id", %{store: store} do
    assert {:error, :not_found} = SessionStore.get(store, "nonexistent")
  end

  test "destroy removes the session immediately", %{store: store} do
    {:ok, id} = SessionStore.create(store, %{user: "alice"})
    assert {:ok, _} = SessionStore.get(store, id)

    assert :ok = SessionStore.destroy(store, id)
    assert {:error, :not_found} = SessionStore.get(store, id)
  end

  test "destroy returns :ok even for unknown session", %{store: store} do
    assert :ok = SessionStore.destroy(store, "nonexistent")
  end

  # -------------------------------------------------------
  # Update
  # -------------------------------------------------------

  test "update replaces session data", %{store: store} do
    {:ok, id} = SessionStore.create(store, %{user: "alice", count: 0})

    assert {:ok, %{user: "alice", count: 42}} =
             SessionStore.update(store, id, %{user: "alice", count: 42})

    assert {:ok, %{user: "alice", count: 42}} = SessionStore.get(store, id)
  end

  test "update returns error for unknown session", %{store: store} do
    assert {:error, :not_found} = SessionStore.update(store, "nonexistent", %{})
  end

  # -------------------------------------------------------
  # Inactivity expiration
  # -------------------------------------------------------

  test "session expires after inactivity timeout", %{store: store} do
    {:ok, id} = SessionStore.create(store, %{user: "alice"})

    Clock.advance(1_001)

    assert {:error, :not_found} = SessionStore.get(store, id)
  end

  test "session is still alive just before timeout", %{store: store} do
    {:ok, id} = SessionStore.create(store, %{user: "alice"})

    Clock.advance(999)

    assert {:ok, %{user: "alice"}} = SessionStore.get(store, id)
  end

  # -------------------------------------------------------
  # Touch resets the timer
  # -------------------------------------------------------

  test "touch resets the inactivity timer", %{store: store} do
    {:ok, id} = SessionStore.create(store, %{user: "alice"})

    # Advance to 800ms — still alive
    Clock.advance(800)
    assert :ok = SessionStore.touch(store, id)

    # Advance another 800ms (total 1600ms from creation, 800ms from touch)
    Clock.advance(800)
    assert {:ok, %{user: "alice"}} = SessionStore.get(store, id)
  end

  test "touch returns error for unknown session", %{store: store} do
    assert {:error, :not_found} = SessionStore.touch(store, "nonexistent")
  end

  test "touch returns error for expired session", %{store: store} do
    {:ok, id} = SessionStore.create(store, %{user: "alice"})

    Clock.advance(1_001)

    assert {:error, :not_found} = SessionStore.touch(store, id)
  end

  # -------------------------------------------------------
  # Get resets the timer
  # -------------------------------------------------------

  test "get resets the inactivity timer", %{store: store} do
    {:ok, id} = SessionStore.create(store, %{user: "alice"})

    # Advance to 800ms, then get (resets timer)
    Clock.advance(800)
    assert {:ok, _} = SessionStore.get(store, id)

    # Advance another 800ms (total 1600ms from creation, 800ms from get)
    Clock.advance(800)
    assert {:ok, %{user: "alice"}} = SessionStore.get(store, id)
  end

  # -------------------------------------------------------
  # Update resets the timer
  # -------------------------------------------------------

  test "update resets the inactivity timer", %{store: store} do
    {:ok, id} = SessionStore.create(store, %{user: "alice"})

    Clock.advance(800)
    assert {:ok, _} = SessionStore.update(store, id, %{user: "alice", visits: 1})

    # 800ms since update — should still be alive
    Clock.advance(800)
    assert {:ok, %{user: "alice", visits: 1}} = SessionStore.get(store, id)
  end

  test "update returns error for expired session", %{store: store} do
    {:ok, id} = SessionStore.create(store, %{user: "alice"})

    Clock.advance(1_001)

    assert {:error, :not_found} = SessionStore.update(store, id, %{user: "alice"})
  end

  # -------------------------------------------------------
  # Session independence
  # -------------------------------------------------------

  test "sessions are fully independent", %{store: store} do
    {:ok, id_a} = SessionStore.create(store, %{user: "alice"})

    Clock.advance(500)
    {:ok, id_b} = SessionStore.create(store, %{user: "bob"})

    # At time 1001: alice expires, bob still has ~500ms left
    Clock.advance(501)

    assert {:error, :not_found} = SessionStore.get(store, id_a)
    assert {:ok, %{user: "bob"}} = SessionStore.get(store, id_b)
  end

  test "destroying one session does not affect another", %{store: store} do
    {:ok, id_a} = SessionStore.create(store, %{user: "alice"})
    {:ok, id_b} = SessionStore.create(store, %{user: "bob"})

    SessionStore.destroy(store, id_a)

    assert {:error, :not_found} = SessionStore.get(store, id_a)
    assert {:ok, %{user: "bob"}} = SessionStore.get(store, id_b)
  end

  # -------------------------------------------------------
  # Multiple touch / get cycles keep session alive
  # -------------------------------------------------------

  test "repeated touches keep a session alive indefinitely", %{store: store} do
    {:ok, id} = SessionStore.create(store, %{user: "alice"})

    # Touch every 800ms for 5 cycles — total elapsed 4000ms >> timeout of 1000ms
    for _ <- 1..5 do
      Clock.advance(800)
      assert :ok = SessionStore.touch(store, id)
    end

    assert {:ok, %{user: "alice"}} = SessionStore.get(store, id)
  end

  # -------------------------------------------------------
  # Cleanup (memory leak prevention)
  # -------------------------------------------------------

  test "expired sessions are cleaned up by sweep", %{store: store} do
    # Create 100 sessions
    ids =
      for i <- 1..100 do
        {:ok, id} = SessionStore.create(store, %{index: i})
        id
      end

    # Advance past all timeouts
    Clock.advance(1_100)

    # Trigger cleanup
    send(store, :cleanup)
    :sys.get_state(store)

    # Internal state should be empty
    state = :sys.get_state(store)
    assert map_size(state.sessions) == 0

    # Confirm all sessions are gone
    for id <- ids do
      assert {:error, :not_found} = SessionStore.get(store, id)
    end
  end

  test "cleanup only removes expired sessions, keeps active ones", %{store: store} do
    {:ok, old_id} = SessionStore.create(store, %{user: "old"})

    Clock.advance(900)
    {:ok, new_id} = SessionStore.create(store, %{user: "new"})

    # At 1001: old expired, new still has ~900ms
    Clock.advance(101)

    send(store, :cleanup)
    :sys.get_state(store)

    assert {:error, :not_found} = SessionStore.get(store, old_id)
    assert {:ok, %{user: "new"}} = SessionStore.get(store, new_id)
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "session with minimal timeout (1ms)", %{store: _store} do
    # Override timeout per-test by starting a new store
    {:ok, short} =
      SessionStore.start_link(
        clock: &Clock.now/0,
        timeout_ms: 1,
        cleanup_interval_ms: :infinity
      )

    {:ok, id} = SessionStore.create(short, %{flash: true})
    assert {:ok, _} = SessionStore.get(short, id)

    Clock.advance(2)
    assert {:error, :not_found} = SessionStore.get(short, id)
  end

  test "create works with various data types", %{store: store} do
    {:ok, id1} = SessionStore.create(store, "just a string")
    {:ok, id2} = SessionStore.create(store, [1, 2, 3])
    {:ok, id3} = SessionStore.create(store, {:tuple, :data})

    assert {:ok, "just a string"} = SessionStore.get(store, id1)
    assert {:ok, [1, 2, 3]} = SessionStore.get(store, id2)
    assert {:ok, {:tuple, :data}} = SessionStore.get(store, id3)
  end
end
