  test "counter-based ids start at pay_1 and increment by one per record", %{pid: pid} do
    {:ok, r1} = IdempotentPayments.process_payment(pid, @valid_params)
    {:ok, r2} = IdempotentPayments.process_payment(pid, @valid_params, "seq-key")
    # Cache hit: must not consume an id.
    {:ok, r2_replay} = IdempotentPayments.process_payment(pid, @valid_params, "seq-key")
    {:ok, r3} = IdempotentPayments.process_payment(pid, @valid_params)

    assert r1.id == "pay_1"
    assert r2.id == "pay_2"
    assert r2_replay.id == "pay_2"
    assert r3.id == "pay_3"

    ids = pid |> IdempotentPayments.get_payments() |> Enum.map(& &1.id)
    assert ids == ["pay_1", "pay_2", "pay_3"]

    assert {:ok, found} = IdempotentPayments.get_payment(pid, "pay_2")
    assert found.id == "pay_2"
  end