  test "start_link with no arguments starts an empty server" do
    {:ok, pid} = RateLimiter.start_link()
    assert is_pid(pid)

    # Freshly started with zero keys tracked: the first check for any key is
    # allowed with remaining = max - 1, independent of the (real) clock value.
    assert {:ok, 4} = RateLimiter.check(pid, "fresh", 5, 1_000)
  end