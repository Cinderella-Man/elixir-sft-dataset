  test "generated token verifies successfully" do
    token = generate(%{user_id: 42}, "secret", 300)
    assert is_binary(token)
    assert {:ok, %{user_id: 42}} = verify(token, "secret")
  end