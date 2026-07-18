  test "supports integer payload" do
    token = generate(12345, "s", 60)
    assert {:ok, 12345} = verify(token, "s")
  end