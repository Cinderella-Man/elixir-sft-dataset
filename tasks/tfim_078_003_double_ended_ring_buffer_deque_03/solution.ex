  test "push_back appends to the back" do
    d =
      RingDeque.new(5)
      |> RingDeque.push_back(1)
      |> RingDeque.push_back(2)
      |> RingDeque.push_back(3)

    assert RingDeque.to_list(d) == [1, 2, 3]
    assert {:ok, 1} = RingDeque.peek_front(d)
    assert {:ok, 3} = RingDeque.peek_back(d)
  end