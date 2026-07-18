  test "supports deeply nested map payload" do
    payload = %{a: %{b: %{c: "deep"}}}
    token = generate(payload, "s", 60)
    assert {:ok, ^payload} = verify(token, "s")
  end