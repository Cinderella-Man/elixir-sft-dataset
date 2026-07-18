  test "size of a one and two element tree is exactly one and two" do
    one = build([{3, 4}])
    assert T.size(one) == 1

    two = T.insert(one, {5, 6})
    assert T.size(two) == 2

    # Duplicates each count separately.
    three = T.insert(two, {3, 4})
    assert T.size(three) == 3

    # Every earlier version keeps its own count.
    assert T.size(one) == 1
    assert T.size(two) == 2
  end