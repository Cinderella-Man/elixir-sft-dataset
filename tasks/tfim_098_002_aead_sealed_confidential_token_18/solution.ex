  test "supports atom payload" do
    token = seal(:hello, @key, 60)
    assert {:ok, :hello} = open(token, @key)
  end