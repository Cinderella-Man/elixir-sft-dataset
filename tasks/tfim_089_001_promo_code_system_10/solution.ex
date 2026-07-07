  test "free_shipping returns the configured waived shipping amount" do
    {:ok, _} = PromoCodes.create(%{code: "SHIP", type: :free_shipping, value: 999})
    assert {:ok, 999} = PromoCodes.apply("SHIP", 10_000)
  end