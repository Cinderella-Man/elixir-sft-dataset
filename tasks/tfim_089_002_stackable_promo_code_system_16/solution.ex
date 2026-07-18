  test "expired code is rejected once the clock advances" do
    valid_until = ~U[2026-06-10 00:00:00Z]

    {:ok, _} =
      StackablePromoCodes.create(%{
        code: "WIN",
        type: :percentage,
        value: 10,
        valid_until: valid_until
      })

    assert {:ok, r} = StackablePromoCodes.apply_codes(["WIN"], 10_000)
    assert find(r.applied, "WIN").discount == 1_000

    Clock.set(~U[2026-06-11 00:00:00Z])
    assert {:ok, r2} = StackablePromoCodes.apply_codes(["WIN"], 10_000)
    assert find(r2.rejected, "WIN").reason == :expired
  end