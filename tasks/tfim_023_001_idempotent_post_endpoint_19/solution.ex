  test "cleanup keeps idempotency entries that have not expired yet", %{pid: pid} do
    {:ok, old_resp} = IdempotentPayments.process_payment(pid, @valid_params, "old-key")

    Clock.advance(6_000)
    {:ok, fresh_resp} = IdempotentPayments.process_payment(pid, @valid_params, "fresh-key")

    # now = 11_000: "old-key" expired at 10_000, "fresh-key" expires at 16_000
    Clock.advance(5_000)
    send(pid, :cleanup)

    # The unexpired entry must survive the sweep: replay is still a cache hit.
    assert {:ok, ^fresh_resp} =
             IdempotentPayments.process_payment(pid, @valid_params, "fresh-key")

    # The expired entry is gone: replay reprocesses into a brand new record.
    assert {:ok, replay} = IdempotentPayments.process_payment(pid, @valid_params, "old-key")
    assert replay.id != old_resp.id

    ids = pid |> IdempotentPayments.get_payments() |> Enum.map(& &1.id)
    assert length(ids) == 3
    assert old_resp.id in ids
    assert fresh_resp.id in ids
  end