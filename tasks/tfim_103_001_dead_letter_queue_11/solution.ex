  test "a raising handler does not crash the DLQ and keeps the message", %{dlq: dlq} do
    {:ok, id} = DLQ.push(dlq, "q", :msg, :orig, %{})

    assert {:error, _reason} =
             DLQ.retry(dlq, "q", id, fn _ -> raise "kaboom" end)

    assert Process.alive?(dlq)
    assert [entry] = DLQ.peek(dlq, "q", 10)
    assert entry.retry_count == 1

    # server still usable afterwards
    assert :ok = DLQ.retry(dlq, "q", id, fn _ -> :ok end)
    assert DLQ.peek(dlq, "q", 10) == []
  end