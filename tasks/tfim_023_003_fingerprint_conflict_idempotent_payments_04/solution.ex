  test "same key with different params is a conflict and does not mutate the entry", %{pid: pid} do
    {:ok, first} = StrictIdempotentPayments.process_payment(pid, @valid, "lock")

    conflict =
      StrictIdempotentPayments.process_payment(
        pid,
        %{amount: 99_999, currency: "EUR", recipient: "someone_else"},
        "lock"
      )

    assert conflict == {:error, :idempotency_key_conflict}
    # No new record was created by the conflicting replay
    assert length(StrictIdempotentPayments.get_payments(pid)) == 1

    # The original entry is untouched: replaying the original params still works
    {:ok, again} = StrictIdempotentPayments.process_payment(pid, @valid, "lock")
    assert again == first
    assert length(StrictIdempotentPayments.get_payments(pid)) == 1
  end