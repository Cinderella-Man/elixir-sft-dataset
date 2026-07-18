  test "expiry outranks the minimum-order check for the same code" do
    {:ok, _} =
      StackablePromoCodes.create(%{
        code: "OLD",
        type: :fixed_amount,
        value: 500,
        min_order_total: 50_000,
        valid_until: ~U[2026-05-01 00:00:00Z]
      })

    assert {:ok, r} = StackablePromoCodes.apply_codes(["OLD"], 1_000)
    assert find(r.rejected, "OLD").reason == :expired
    assert r.applied == []
    assert r.total_discount == 0
  end