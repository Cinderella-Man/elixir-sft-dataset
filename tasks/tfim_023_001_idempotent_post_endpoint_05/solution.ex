  test "cached response is returned even if params differ on replay", %{pid: pid} do
    key = "idem-lock"

    {:ok, first} =
      IdempotentPayments.process_payment(pid, @valid_params, key)

    # Second call with different amount — should still return original cached response
    {:ok, second} =
      IdempotentPayments.process_payment(
        pid,
        %{amount: 99_999, currency: "EUR", recipient: "someone_else"},
        key
      )

    assert first == second
    assert length(IdempotentPayments.get_payments(pid)) == 1
  end