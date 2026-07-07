  test "delete on empty tree reports not_found" do
    assert {:error, :not_found} = T.delete(T.new(), {1, 2})
  end