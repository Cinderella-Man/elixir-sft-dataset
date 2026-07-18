  test "total max_uses is enforced" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "TWICE",
        type: :fixed_amount,
        value: 500,
        max_uses: 2
      })

    assert {:ok, 500} = PromoCodes.apply("TWICE", 10_000)
    assert {:ok, 500} = PromoCodes.apply("TWICE", 10_000)
    assert {:error, :max_uses_exceeded} = PromoCodes.apply("TWICE", 10_000)
  end