  test "sealed token opens successfully" do
    token = seal(%{user_id: 42}, @key, 300)
    assert is_binary(token)
    assert {:ok, %{user_id: 42}} = open(token, @key)
  end