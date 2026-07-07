  test "empty code list returns :no_codes" do
    assert {:error, :no_codes} = StackablePromoCodes.apply_codes([], 10_000)
  end