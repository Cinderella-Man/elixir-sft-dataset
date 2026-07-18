  test "time window is enforced with inclusive boundaries" do
    {:ok, _} = TieredPromoCodes.create(%{code: "SOON", tiers: @pct_tiers, valid_from: @future})
    assert {:error, :not_yet_valid} = TieredPromoCodes.apply_code("SOON", 10_000)

    {:ok, _} = TieredPromoCodes.create(%{code: "OLD", tiers: @pct_tiers, valid_until: @past})
    assert {:error, :expired} = TieredPromoCodes.apply_code("OLD", 10_000)

    {:ok, _} =
      TieredPromoCodes.create(%{
        code: "EDGE",
        tiers: @pct_tiers,
        valid_from: Clock.base(),
        valid_until: Clock.base()
      })

    assert {:ok, 2_000} = TieredPromoCodes.apply_code("EDGE", 10_000)
  end