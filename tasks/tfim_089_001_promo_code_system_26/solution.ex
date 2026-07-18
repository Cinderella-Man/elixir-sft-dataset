  test "an anonymous application does not consume any user's per-user quota" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "ANONPU",
        type: :fixed_amount,
        value: 500,
        max_uses_per_user: 1
      })

    # No :user_id -> counts toward the (unlimited) total, tracked for nobody.
    assert {:ok, 500} = PromoCodes.apply("ANONPU", 10_000)
    assert {:ok, 500} = PromoCodes.apply("ANONPU", 10_000)

    # u1 still has their full per-user allowance.
    assert {:ok, 500} = PromoCodes.apply("ANONPU", 10_000, user_id: "u1")

    assert {:error, :max_uses_per_user_exceeded} =
             PromoCodes.apply("ANONPU", 10_000, user_id: "u1")
  end