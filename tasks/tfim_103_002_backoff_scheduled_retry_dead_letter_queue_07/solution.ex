  test "ready/3 excludes not-yet-due messages and includes them after the backoff elapses", %{
    dlq: dlq
  } do
    {:ok, id} = BackoffDLQ.push(dlq, "q", :m, :orig, %{})
    assert {:error, :boom} = BackoffDLQ.retry(dlq, "q", id, fn _ -> {:error, :boom} end)

    assert BackoffDLQ.ready(dlq, "q", 10) == []
    Clock.advance(1000)
    assert [r] = BackoffDLQ.ready(dlq, "q", 10)
    assert r.id == id
  end