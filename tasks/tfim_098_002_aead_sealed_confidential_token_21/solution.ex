  test "supports deeply nested map payload" do
    payload = %{a: %{b: %{c: "deep"}}}
    token = seal(payload, @key, 60)
    assert {:ok, ^payload} = open(token, @key)
  end