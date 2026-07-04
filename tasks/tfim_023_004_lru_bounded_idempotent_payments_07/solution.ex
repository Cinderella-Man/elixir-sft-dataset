  test "textbook LRU trace with touch-protection", %{pid: _pid} do
    {:ok, pid} = BoundedIdempotentPayments.start_link(clock: &Clock.now/0, max_keys: 2)

    {:ok, a1} = BoundedIdempotentPayments.process_payment(pid, @valid, "a")
    {:ok, _b1} = BoundedIdempotentPayments.process_payment(pid, @valid, "b")

    # touch "a" -> "b" becomes LRU
    {:ok, a_hit} = BoundedIdempotentPayments.process_payment(pid, @valid, "a")
    assert a_hit == a1
    assert BoundedIdempotentPayments.keys_by_recency(pid) == ["b", "a"]

    # "c" overflows -> evicts "b" (not the touched "a")
    {:ok, _c1} = BoundedIdempotentPayments.process_payment(pid, @valid, "c")
    assert BoundedIdempotentPayments.keys_by_recency(pid) == ["a", "c"]

    # "a" still cached (same id), "b" was evicted -> fresh record
    {:ok, a_again} = BoundedIdempotentPayments.process_payment(pid, @valid, "a")
    assert a_again == a1

    {:ok, b2} = BoundedIdempotentPayments.process_payment(pid, @valid, "b")
    assert b2.id != a1.id

    # a -> pay_1, b -> pay_2, c -> pay_3, b(again) -> pay_4
    assert length(BoundedIdempotentPayments.get_payments(pid)) == 4
  end