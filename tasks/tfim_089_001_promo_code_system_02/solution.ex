  test "create returns {:ok, code} for a valid percentage code" do
    assert {:ok, _code} =
             PromoCodes.create(%{code: "SAVE20", type: :percentage, value: 20})
  end