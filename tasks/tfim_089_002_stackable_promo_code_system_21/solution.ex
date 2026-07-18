  test "max_uses and max_uses_per_user default to unlimited applications" do
    {:ok, _} = StackablePromoCodes.create(%{code: "FREE", type: :fixed_amount, value: 100})

    for _ <- 1..3 do
      assert {:ok, r} = StackablePromoCodes.apply_codes(["FREE"], 10_000, user_id: "u1")
      assert find(r.applied, "FREE").discount == 100
      assert r.rejected == []
    end
  end