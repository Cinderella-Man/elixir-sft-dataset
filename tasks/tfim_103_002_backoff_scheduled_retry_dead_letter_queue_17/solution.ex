  test "max_attempts defaults to 5 failed retries before the message dies" do
    {:ok, dlq} = BackoffDLQ.start_link(clock: &Clock.now/0)
    {:ok, id} = BackoffDLQ.push(dlq, "q", :m, :orig, %{})
    fail = fn _ -> {:error, :again} end

    # default backoffs from the default base: 1000, 2000, 4000, 8000
    for advance <- [0, 1000, 2000, 4000] do
      Clock.advance(advance)
      assert {:error, :again} = BackoffDLQ.retry(dlq, "q", id, fail)
    end

    # four failures is not yet enough under the default
    assert [e4] = BackoffDLQ.peek(dlq, "q", 10)
    assert e4.retry_count == 4
    assert e4.status == :pending

    Clock.advance(8000)
    assert {:error, :again} = BackoffDLQ.retry(dlq, "q", id, fail)
    assert [e5] = BackoffDLQ.peek(dlq, "q", 10)
    assert e5.retry_count == 5
    assert e5.status == :dead
    assert {:error, :dead} = BackoffDLQ.retry(dlq, "q", id, fn _ -> :ok end)
  end