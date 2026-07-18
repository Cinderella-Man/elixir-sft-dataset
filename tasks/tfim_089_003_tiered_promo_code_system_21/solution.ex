  test "max_uses failure outranks the per-user failure when both are exhausted" do
    {:ok, _} =
      TieredPromoCodes.create(%{
        code: "BOTH",
        tiers: @pct_tiers,
        max_uses: 1,
        max_uses_per_user: 1
      })

    assert {:ok, 2_000} = TieredPromoCodes.apply_code("BOTH", 10_000, user_id: "u1")

    assert {:error, :max_uses_exceeded} =
             TieredPromoCodes.apply_code("BOTH", 10_000, user_id: "u1")
  end