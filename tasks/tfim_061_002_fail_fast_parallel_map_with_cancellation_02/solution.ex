  test "empty collection returns {:ok, []}" do
    assert {:ok, []} = FailFastMap.pmap([], fn x -> x end, 3)
  end