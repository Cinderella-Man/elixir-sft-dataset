  test "tokens are not cross-verifiable across secrets" do
    t1 = generate("msg", "secret-a", 300)
    t2 = generate("msg", "secret-b", 300)

    assert {:ok, "msg"} = verify(t1, "secret-a")
    assert {:ok, "msg"} = verify(t2, "secret-b")

    assert {:error, :invalid_signature} = verify(t1, "secret-b")
    assert {:error, :invalid_signature} = verify(t2, "secret-a")
  end