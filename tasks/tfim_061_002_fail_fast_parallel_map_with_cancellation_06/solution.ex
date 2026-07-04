  test "first failure returns {:error, {index, reason}}" do
    assert {:error, {5, _reason}} =
             FailFastMap.pmap(1..6, fn
               6 -> raise "boom"
               x -> x * 2
             end, 2)
  end