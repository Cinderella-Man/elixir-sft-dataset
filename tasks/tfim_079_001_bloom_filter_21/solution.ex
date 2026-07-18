  test "add/2 yields equal structs regardless of insertion order" do
    empty = BloomFilter.new(100, 0.01)
    items = ["x", :y, 3, {4, "z"}, [5, 6]]

    build = fn list -> Enum.reduce(list, empty, &BloomFilter.add(&2, &1)) end

    forward = build.(items)
    backward = build.(Enum.reverse(items))
    rotated = build.(tl(items) ++ [hd(items)])

    assert forward == backward
    assert forward == rotated
    assert forward.bits == rotated.bits
  end