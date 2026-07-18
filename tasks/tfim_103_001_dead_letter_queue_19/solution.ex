  test "purge removes a message whose age is exactly equal to older_than", %{dlq: dlq} do
    {:ok, exact} = DLQ.push(dlq, "q", :exact, :err, %{})

    Clock.advance(500)
    {:ok, younger} = DLQ.push(dlq, "q", :younger, :err, %{})

    Clock.advance(500)
    # now = 1000: :exact age = 1000 (== 1000 -> purged), :younger age = 500 (kept)
    assert {:ok, 1} = DLQ.purge(dlq, "q", 1_000)

    assert [entry] = DLQ.peek(dlq, "q", 10)
    assert entry.id == younger
    refute entry.id == exact
  end