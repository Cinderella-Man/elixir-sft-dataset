  test "pop_front and pop_back remove the right ends" do
    d =
      RingDeque.new(4)
      |> RingDeque.push_back(1)
      |> RingDeque.push_back(2)
      |> RingDeque.push_back(3)
      |> RingDeque.push_back(4)

    assert {:ok, 1, d} = RingDeque.pop_front(d)
    assert {:ok, 4, d} = RingDeque.pop_back(d)
    assert RingDeque.to_list(d) == [2, 3]
    assert {:ok, 3, d} = RingDeque.pop_back(d)
    assert {:ok, 2, d} = RingDeque.pop_front(d)
    assert RingDeque.size(d) == 0
  end