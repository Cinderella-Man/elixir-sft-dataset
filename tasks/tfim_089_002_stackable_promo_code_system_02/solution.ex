  test "create returns {:ok, code} for a valid code" do
    assert {:ok, _} = StackablePromoCodes.create(%{code: "P20", type: :percentage, value: 20})
  end