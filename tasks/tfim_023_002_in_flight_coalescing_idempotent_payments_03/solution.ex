  test "concurrent requests with same key coalesce into one processing", %{pid: pid} do
    tasks =
      for _ <- 1..10 do
        Task.async(fn -> CoalescingPayments.process_payment(pid, @valid, "same-key") end)
      end

    results = Task.await_many(tasks, 5000)

    # All ten callers received the identical shared result
    assert Enum.uniq(results) |> length() == 1
    assert [{:ok, _}] = Enum.uniq(results)

    # Processor ran exactly once, and exactly one payment record was created
    assert Calls.count() == 1
    assert length(CoalescingPayments.get_payments(pid)) == 1
  end