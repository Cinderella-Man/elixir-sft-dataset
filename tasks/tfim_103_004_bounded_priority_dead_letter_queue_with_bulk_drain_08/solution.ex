  test "drain removes successes and keeps failures (bumping retry_count)", %{dlq: dlq} do
    {:ok, _} = PriorityDLQ.push(dlq, "q", :ok_msg, :err, %{}, :high)
    {:ok, _} = PriorityDLQ.push(dlq, "q", :fail_msg, :err, %{}, :normal)

    handler = fn
      :ok_msg -> :ok
      :fail_msg -> {:error, :boom}
    end

    assert {:ok, stats} = PriorityDLQ.drain(dlq, "q", handler, 10)
    assert stats.succeeded == 1
    assert stats.failed == 1

    assert [e] = PriorityDLQ.peek(dlq, "q", 10)
    assert e.message == :fail_msg
    assert e.retry_count == 1
  end