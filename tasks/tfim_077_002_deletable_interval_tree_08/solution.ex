  test "member? reflects presence" do
    tree = build([{1, 5}, {10, 20}])
    assert T.member?(tree, {1, 5})
    assert T.member?(tree, {10, 20})
    refute T.member?(tree, {1, 6})
    refute T.member?(tree, {2, 5})
  end