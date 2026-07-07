  test "mixed front/back pushes interleave correctly" do
    d =
      RingDeque.new(5)
      |> RingDeque.push_back(:b)
      |> RingDeque.push_front(:a)
      |> RingDeque.push_back(:c)
      |> RingDeque.push_front(:z)

    assert RingDeque.to_list(d) == [:z, :a, :b, :c]
  end