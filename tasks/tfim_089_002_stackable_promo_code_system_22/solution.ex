  test "max_uses counts applications across all users" do
    {:ok, _} =
      StackablePromoCodes.create(%{code: "CAP2", type: :fixed_amount, value: 500, max_uses: 2})

    assert {:ok, r1} = StackablePromoCodes.apply_codes(["CAP2"], 10_000, user_id: "u1")
    assert find(r1.applied, "CAP2").discount == 500
    assert {:ok, r2} = StackablePromoCodes.apply_codes(["CAP2"], 10_000, user_id: "u2")
    assert find(r2.applied, "CAP2").discount == 500
    assert {:ok, r3} = StackablePromoCodes.apply_codes(["CAP2"], 10_000, user_id: "u3")
    assert find(r3.rejected, "CAP2").reason == :max_uses_exceeded
    assert r3.applied == []
  end