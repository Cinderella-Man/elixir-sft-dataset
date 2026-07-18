  test "cached error replays even when the replay carries valid params", %{pid: pid} do
    key = "idem-error-then-valid"

    assert {:error, :invalid_params} =
             IdempotentPayments.process_payment(pid, %{amount: 100}, key)

    # Same key, now with fully valid params: the cached error must win, and no
    # payment record may be created.
    assert {:error, :invalid_params} =
             IdempotentPayments.process_payment(pid, @valid_params, key)

    assert IdempotentPayments.get_payments(pid) == []
  end