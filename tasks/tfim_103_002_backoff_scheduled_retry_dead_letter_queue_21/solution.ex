  test "peek and ready entries carry the error_reason and metadata given at push", %{dlq: dlq} do
    meta = %{src: "web", attempt: 2}
    {:ok, id} = BackoffDLQ.push(dlq, "q", %{body: "hi"}, {:http, 503}, meta)

    assert [e] = BackoffDLQ.peek(dlq, "q", 10)
    assert e.id == id
    assert e.message == %{body: "hi"}
    assert e.error_reason == {:http, 503}
    assert e.metadata == meta

    assert [r] = BackoffDLQ.ready(dlq, "q", 10)
    assert r.error_reason == {:http, 503}
    assert r.metadata == meta

    # the original error_reason survives a failed retry with a different reason
    assert {:error, :other} = BackoffDLQ.retry(dlq, "q", id, fn _ -> {:error, :other} end)
    assert [e2] = BackoffDLQ.peek(dlq, "q", 10)
    assert e2.error_reason == {:http, 503}
    assert e2.metadata == meta
  end