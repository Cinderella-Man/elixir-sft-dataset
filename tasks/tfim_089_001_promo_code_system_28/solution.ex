  test "total max_uses failure takes precedence over the per-user limit failure" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "PRECUSES",
        type: :fixed_amount,
        value: 500,
        max_uses: 1,
        max_uses_per_user: 1
      })

    assert {:ok, 500} = PromoCodes.apply("PRECUSES", 10_000, user_id: "u1")

    # Both limits are now blown for u1; the total limit is checked first.
    assert {:error, :max_uses_exceeded} =
             PromoCodes.apply("PRECUSES", 10_000, user_id: "u1")
  end