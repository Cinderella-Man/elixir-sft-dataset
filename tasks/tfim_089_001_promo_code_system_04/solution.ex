  test "create rejects an invalid discount type" do
    assert {:error, :invalid_type} =
             PromoCodes.create(%{code: "BAD", type: :bogus, value: 1})
  end