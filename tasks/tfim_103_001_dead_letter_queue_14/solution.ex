  test "purge removes messages at/older than the given age and keeps newer ones", %{dlq: dlq} do
    # A pushed at t=0
    {:ok, _a} = DLQ.push(dlq, "q", :old, :err, %{})

    Clock.advance(1_000)
    # B pushed at t=1000
    {:ok, b} = DLQ.push(dlq, "q", :new, :err, %{})

    # now = 1000. A age = 1000 (>= 500 -> purged), B age = 0 (kept)
    assert {:ok, 1} = DLQ.purge(dlq, "q", 500)

    assert [entry] = DLQ.peek(dlq, "q", 10)
    assert entry.id == b
    assert entry.message == :new
  end