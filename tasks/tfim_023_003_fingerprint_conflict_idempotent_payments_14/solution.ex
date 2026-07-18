  test "payment IDs are counter-based and start at pay_1", %{pid: pid} do
    {:ok, r1} = StrictIdempotentPayments.process_payment(pid, @valid)
    {:ok, r2} = StrictIdempotentPayments.process_payment(pid, @valid, "counted")
    {:ok, r3} = StrictIdempotentPayments.process_payment(pid, @valid)

    assert r1.id == "pay_1"
    assert r2.id == "pay_2"
    assert r3.id == "pay_3"

    assert {:ok, %{id: "pay_1"}} = StrictIdempotentPayments.get_payment(pid, "pay_1")
    assert {:ok, %{id: "pay_3"}} = StrictIdempotentPayments.get_payment(pid, "pay_3")
    assert {:error, :not_found} = StrictIdempotentPayments.get_payment(pid, "pay_4")

    assert Enum.map(StrictIdempotentPayments.get_payments(pid), & &1.id) ==
             ["pay_1", "pay_2", "pay_3"]
  end