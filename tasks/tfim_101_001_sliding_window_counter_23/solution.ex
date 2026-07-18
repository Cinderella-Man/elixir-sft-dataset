  test "name option registers the process and is not treated as counter config", %{sc: _sc} do
    name = :sliding_counter_named_instance

    {:ok, pid} =
      SlidingCounter.start_link(
        name: name,
        clock: &Clock.now/0,
        bucket_ms: 100,
        cleanup_interval_ms: :infinity
      )

    # Registered: the name works as a server reference and behaves normally.
    assert :ok = SlidingCounter.increment(name, "k")
    assert 1 = SlidingCounter.count(name, "k", 1_000)

    # Forwarded as a start option, so a second start under the same name reports
    # the standard GenServer.on_start() error rather than starting a twin.
    assert {:error, {:already_started, ^pid}} =
             SlidingCounter.start_link(
               name: name,
               clock: &Clock.now/0,
               cleanup_interval_ms: :infinity
             )
  end