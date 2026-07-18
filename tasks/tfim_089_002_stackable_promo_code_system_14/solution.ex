  test "only applied codes consume uses" do
    {:ok, _} =
      StackablePromoCodes.create(%{code: "ONCE", type: :fixed_amount, value: 500, max_uses: 1})

    {:ok, _} = StackablePromoCodes.create(%{code: "DUPE", type: :percentage, value: 10})
    {:ok, _} = StackablePromoCodes.create(%{code: "DUPE2", type: :percentage, value: 20})

    # DUPE loses to DUPE2 and is rejected -> must not consume
    assert {:ok, _} = StackablePromoCodes.apply_codes(["ONCE", "DUPE", "DUPE2"], 10_000)
    assert {:ok, r} = StackablePromoCodes.apply_codes(["ONCE"], 10_000)
    assert find(r.rejected, "ONCE").reason == :max_uses_exceeded

    # DUPE was never consumed, still usable
    assert {:ok, r2} = StackablePromoCodes.apply_codes(["DUPE"], 10_000)
    assert find(r2.applied, "DUPE").discount == 1_000
  end