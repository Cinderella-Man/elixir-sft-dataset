# The tests are the spec

Below is a complete, self-contained ExUnit suite. It is the only
specification you get: build the module (or modules) it exercises until
every test passes. Reach for nothing beyond what the tests themselves
require — the standard library and OTP unless the suite says otherwise.
House style applies (`@moduledoc`, `@doc` + `@spec` on the public API,
no compiler warnings).

## The test suite

```elixir
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

  # A synchronous read on an id that was never created: it returns
  # {:error, :not_found} without touching any session, and because the server
  # handles messages in order, it only replies once the preceding :cleanup
  # message has been fully processed.
  defp await_cleanup(store) do
    assert {:error, :not_found} = SessionStore.get(store, "no-such-session")
    :ok
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
    await_cleanup(store)

    # Every swept session is unreachable through the public API
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
    await_cleanup(store)

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

  test "default timeout_ms is 30 minutes when the option is omitted" do
    {:ok, store} =
      SessionStore.start_link(clock: &Clock.now/0, cleanup_interval_ms: :infinity)

    {:ok, id_a} = SessionStore.create(store, %{user: "a"})
    {:ok, id_b} = SessionStore.create(store, %{user: "b"})

    # Just under 30 minutes: still alive (upper bound on the default).
    Clock.advance(1_799_999)
    assert {:ok, %{user: "a"}} = SessionStore.get(store, id_a)

    # Just past 30 minutes from creation: expired (lower bound on the default).
    Clock.advance(2)
    assert {:error, :not_found} = SessionStore.get(store, id_b)
  end

  test "session ids are unpadded url-safe base64 of 16 random bytes", %{store: store} do
    {:ok, id} = SessionStore.create(store, %{user: "alice"})

    # 16 bytes base64-encoded without padding is exactly 22 characters.
    assert String.length(id) == 22
    refute String.contains?(id, "=")
    assert id =~ ~r/\A[A-Za-z0-9_-]+\z/
  end

  # -------------------------------------------------------
  # Automatic periodic sweep
  # -------------------------------------------------------

  # Discards clock reads already in the mailbox, so any read observed after
  # this point belongs to work the server started later.
  defp drain_clock_reads do
    receive do
      :clock_read -> drain_clock_reads()
    after
      0 -> :ok
    end
  end

  # Polls until the expired session has disappeared without the test ever
  # asking the server to clean up. Each round waits for the server to consult
  # the injected clock on its own, then rewinds the fake clock: a session the
  # server still holds is well inside its timeout at time 0, so {:ok, _} means
  # "still stored" and {:error, :not_found} means the sweep removed it. When it
  # is still stored, the fake clock is pushed back past the deadline and the
  # next automatic round is awaited, until the overall deadline passes.
  defp await_automatic_sweep(store, id, deadline) do
    assert_receive :clock_read, 1_000

    Clock.set(0)

    case SessionStore.get(store, id) do
      {:error, :not_found} ->
        :ok

      {:ok, _data} ->
        assert System.monotonic_time(:millisecond) < deadline,
               "expired session was never removed without an explicit cleanup trigger"

        Clock.set(1_100)
        drain_clock_reads()
        await_automatic_sweep(store, id, deadline)
    end
  end

  test "periodic sweep removes expired sessions on its own and keeps rescheduling" do
    test_pid = self()

    # The injected clock reports every read, so sweeps that the test never
    # requested are observable through the documented clock hook alone.
    clock = fn ->
      now = Clock.now()
      send(test_pid, :clock_read)
      now
    end

    {:ok, store} =
      SessionStore.start_link(clock: clock, timeout_ms: 1_000, cleanup_interval_ms: 25)

    {:ok, id_a} = SessionStore.create(store, %{user: "alice"})

    # Move the fake time past alice's deadline; from here the only thing that
    # can drop her is the server's own periodic timer.
    Clock.set(1_100)
    drain_clock_reads()
    await_automatic_sweep(store, id_a, System.monotonic_time(:millisecond) + 2_000)

    # A second expired session is swept as well, so the sweep is periodic
    # rather than a single run at startup.
    {:ok, id_b} = SessionStore.create(store, %{user: "bob"})

    Clock.set(1_100)
    drain_clock_reads()
    await_automatic_sweep(store, id_b, System.monotonic_time(:millisecond) + 2_000)
  end
end
```

Send back the implementation only — one file, no tests.
