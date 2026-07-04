  test "requests without idempotency key always create new records", %{pid: pid} do
    tasks =
      for _ <- 1..5 do
        Task.async(fn -> CoalescingPayments.process_payment(pid, @valid) end)
      end

    results = Task.await_many(tasks, 5000)
    ids = Enum.map(results, fn {:ok, r} -> r.id end)

    assert length(Enum.uniq(ids)) == 5
    assert Calls.count() == 5
    assert length(CoalescingPayments.get_payments(pid)) == 5
  end