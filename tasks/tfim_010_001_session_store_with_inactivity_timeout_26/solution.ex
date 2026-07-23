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