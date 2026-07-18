  test "a per-user rejection does not consume a total use" do
    {:ok, _} =
      TieredPromoCodes.create(%{
        code: "NOBURN",
        tiers: @pct_tiers,
        max_uses: 2,
        max_uses_per_user: 1
      })

    assert {:ok, 2_000} = TieredPromoCodes.apply_code("NOBURN", 10_000, user_id: "u1")

    assert {:error, :max_uses_per_user_exceeded} =
             TieredPromoCodes.apply_code("NOBURN", 10_000, user_id: "u1")

    # the rejected attempt must not have burned the second total use
    assert {:ok, 2_000} = TieredPromoCodes.apply_code("NOBURN", 10_000, user_id: "u2")

    assert {:error, :max_uses_exceeded} =
             TieredPromoCodes.apply_code("NOBURN", 10_000, user_id: "u3")
  end