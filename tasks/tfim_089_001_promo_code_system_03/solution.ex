  test "create rejects duplicate codes" do
    assert {:ok, _} = PromoCodes.create(%{code: "DUP", type: :percentage, value: 10})

    assert {:error, :already_exists} =
             PromoCodes.create(%{code: "DUP", type: :fixed_amount, value: 500})
  end