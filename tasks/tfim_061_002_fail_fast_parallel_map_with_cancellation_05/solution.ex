  test "works sequentially with max_concurrency of 1" do
    assert {:ok, [9, 1, 4]} = FailFastMap.pmap([3, 1, 2], fn x -> x * x end, 1)
  end