  test "per-user limit is enforced independently" do
    {:ok, _} = TieredPromoCodes.create(%{code: "PU", tiers: @pct_tiers, max_uses_per_user: 1})
    assert {:ok, _} = TieredPromoCodes.apply_code("PU", 10_000, user_id: "u1")

    assert {:error, :max_uses_per_user_exceeded} =
             TieredPromoCodes.apply_code("PU", 10_000, user_id: "u1")

    assert {:ok, _} = TieredPromoCodes.apply_code("PU", 10_000, user_id: "u2")
  end