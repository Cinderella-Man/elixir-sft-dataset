  test "supports atom payload" do
    token = generate(:hello, "s", 60)
    assert {:ok, :hello} = verify(token, "s")
  end