  test "float, negative and non-numeric weights all raise ArgumentError" do
    assert_raise ArgumentError, fn ->
      WeightedMap.pmap([1], fn x -> x end, fn _ -> 1.5 end, 5)
    end

    assert_raise ArgumentError, fn ->
      WeightedMap.pmap([1], fn x -> x end, fn _ -> -2 end, 5)
    end

    assert_raise ArgumentError, fn ->
      WeightedMap.pmap([1], fn x -> x end, fn _ -> :heavy end, 5)
    end

    assert_raise ArgumentError, fn ->
      WeightedMap.pmap([1, 2], fn x -> x end, fn x -> x - 1 end, 5)
    end
  end