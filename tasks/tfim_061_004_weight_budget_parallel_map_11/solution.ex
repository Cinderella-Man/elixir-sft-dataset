  test "invalid weight raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      WeightedMap.pmap([1, 2], fn x -> x end, fn _ -> 0 end, 5)
    end
  end