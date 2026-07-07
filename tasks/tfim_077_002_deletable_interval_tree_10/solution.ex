  test "delete of absent interval returns error and leaves tree usable" do
    tree = build([{1, 5}, {10, 20}])
    assert {:error, :not_found} = T.delete(tree, {2, 9})
    # original still intact
    assert T.member?(tree, {1, 5})
    assert T.size(tree) == 2
  end