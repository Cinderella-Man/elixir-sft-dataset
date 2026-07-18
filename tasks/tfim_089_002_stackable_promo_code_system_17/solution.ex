  test "not-yet-valid and inclusive boundaries" do
    {:ok, _} =
      StackablePromoCodes.create(%{
        code: "SOON",
        type: :percentage,
        value: 10,
        valid_from: @future
      })

    assert {:ok, r} = StackablePromoCodes.apply_codes(["SOON"], 10_000)
    assert find(r.rejected, "SOON").reason == :not_yet_valid

    {:ok, _} =
      StackablePromoCodes.create(%{
        code: "EDGE",
        type: :percentage,
        value: 10,
        valid_from: Clock.base(),
        valid_until: Clock.base()
      })

    assert {:ok, r2} = StackablePromoCodes.apply_codes(["EDGE"], 10_000)
    assert find(r2.applied, "EDGE").discount == 1_000
    assert @past
  end