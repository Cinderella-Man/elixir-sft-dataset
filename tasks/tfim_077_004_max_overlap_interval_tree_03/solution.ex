  test "empty tree has nil busiest point" do
    assert T.busiest_point(T.new()) == nil
  end