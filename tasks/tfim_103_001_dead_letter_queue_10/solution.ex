  test "repeated failing retries accumulate the retry_count", %{dlq: dlq} do
    {:ok, id} = DLQ.push(dlq, "q", :msg, :orig, %{})
    fail = fn _ -> {:error, :again} end

    assert {:error, :again} = DLQ.retry(dlq, "q", id, fail)
    assert {:error, :again} = DLQ.retry(dlq, "q", id, fail)
    assert {:error, :again} = DLQ.retry(dlq, "q", id, fail)

    assert [entry] = DLQ.peek(dlq, "q", 10)
    assert entry.retry_count == 3
  end