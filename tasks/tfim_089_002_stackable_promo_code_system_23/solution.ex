  test "not-yet-valid outranks expired when both window checks fail" do
    {:ok, _} =
      StackablePromoCodes.create(%{
        code: "BOTH",
        type: :percentage,
        value: 10,
        valid_from: @future,
        valid_until: @past
      })

    assert {:ok, r} = StackablePromoCodes.apply_codes(["BOTH"], 10_000)
    assert find(r.rejected, "BOTH").reason == :not_yet_valid
  end