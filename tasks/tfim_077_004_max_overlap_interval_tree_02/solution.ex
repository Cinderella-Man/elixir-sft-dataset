  test "empty tree has zero max overlap" do
    assert T.max_overlap(T.new()) == 0
  end