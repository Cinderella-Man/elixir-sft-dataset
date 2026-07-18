  test "start_link registers the process under the :name option" do
    name = :gcra_limiter_named_instance

    {:ok, _pid} =
      GcraLimiter.start_link(
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity,
        name: name
      )

    # If :name registration worked, the atom itself is a usable server ref.
    assert {:ok, 4} = GcraLimiter.acquire(name, "k", 5.0, 5)
    assert {:ok, 3} = GcraLimiter.acquire(name, "k", 5.0, 5)
  end