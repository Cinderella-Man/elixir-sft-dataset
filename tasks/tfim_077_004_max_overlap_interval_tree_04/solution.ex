  test "depth_at on empty tree is zero" do
    assert T.depth_at(T.new(), 42) == 0
  end