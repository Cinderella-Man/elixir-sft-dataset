  test "empty input is ok with empty forest" do
    assert {:ok, []} = TreeValidator.build([])
  end