  test "supports list payload" do
    token = seal([1, "two", :three], @key, 60)
    assert {:ok, [1, "two", :three]} = open(token, @key)
  end