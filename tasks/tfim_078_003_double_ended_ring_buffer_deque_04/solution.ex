  test "push_front prepends to the front" do
    d =
      RingDeque.new(5)
      |> RingDeque.push_front(1)
      |> RingDeque.push_front(2)
      |> RingDeque.push_front(3)

    assert RingDeque.to_list(d) == [3, 2, 1]
    assert {:ok, 3} = RingDeque.peek_front(d)
    assert {:ok, 1} = RingDeque.peek_back(d)
  end