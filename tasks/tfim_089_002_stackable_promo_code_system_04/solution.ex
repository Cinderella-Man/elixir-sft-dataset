  test "create rejects an invalid type" do
    assert {:error, :invalid_type} =
             StackablePromoCodes.create(%{code: "BAD", type: :bogus, value: 1})
  end