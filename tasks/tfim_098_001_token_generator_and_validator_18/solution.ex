  test "supports list payload" do
    token = generate([1, "two", :three], "s", 60)
    assert {:ok, [1, "two", :three]} = verify(token, "s")
  end