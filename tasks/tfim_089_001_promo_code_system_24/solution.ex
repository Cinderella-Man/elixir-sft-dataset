  test "per-user max_uses is enforced independently per user" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "ONEEACH",
        type: :fixed_amount,
        value: 500,
        max_uses_per_user: 1
      })

    assert {:ok, 500} = PromoCodes.apply("ONEEACH", 10_000, user_id: "u1")

    assert {:error, :max_uses_per_user_exceeded} =
             PromoCodes.apply("ONEEACH", 10_000, user_id: "u1")

    # Different user is unaffected
    assert {:ok, 500} = PromoCodes.apply("ONEEACH", 10_000, user_id: "u2")
  end