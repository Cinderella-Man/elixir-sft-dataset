  test "a successful application by a user also consumes the shared total max_uses" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "SHAREDTOTAL",
        type: :fixed_amount,
        value: 500,
        max_uses: 2
      })

    assert {:ok, 500} = PromoCodes.apply("SHAREDTOTAL", 10_000, user_id: "u1")
    assert {:ok, 500} = PromoCodes.apply("SHAREDTOTAL", 10_000, user_id: "u2")

    # Total is exhausted for everyone, including anonymous callers and new users.
    assert {:error, :max_uses_exceeded} = PromoCodes.apply("SHAREDTOTAL", 10_000)

    assert {:error, :max_uses_exceeded} =
             PromoCodes.apply("SHAREDTOTAL", 10_000, user_id: "u3")
  end