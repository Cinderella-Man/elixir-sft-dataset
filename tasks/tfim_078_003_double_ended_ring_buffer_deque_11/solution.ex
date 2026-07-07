  test "works with mixed value types" do
    d =
      RingDeque.new(5)
      |> RingDeque.push_back(42)
      |> RingDeque.push_back("hello")
      |> RingDeque.push_front(:atom)
      |> RingDeque.push_back({:tuple, 1})
      |> RingDeque.push_front([1, 2, 3])

    assert RingDeque.to_list(d) == [[1, 2, 3], :atom, 42, "hello", {:tuple, 1}]
  end