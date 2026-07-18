  test "per-user limit is enforced independently" do
    {:ok, _} =
      StackablePromoCodes.create(%{
        code: "PU",
        type: :fixed_amount,
        value: 500,
        max_uses_per_user: 1
      })

    assert {:ok, r1} = StackablePromoCodes.apply_codes(["PU"], 10_000, user_id: "u1")
    assert find(r1.applied, "PU")
    assert {:ok, r2} = StackablePromoCodes.apply_codes(["PU"], 10_000, user_id: "u1")
    assert find(r2.rejected, "PU").reason == :max_uses_per_user_exceeded
    assert {:ok, r3} = StackablePromoCodes.apply_codes(["PU"], 10_000, user_id: "u2")
    assert find(r3.applied, "PU").discount == 500
  end