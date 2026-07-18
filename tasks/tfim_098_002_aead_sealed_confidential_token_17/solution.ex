  test "tokens are not cross-openable across keys" do
    t1 = seal("msg", @key_a, 300)
    t2 = seal("msg", @key_b, 300)

    assert {:ok, "msg"} = open(t1, @key_a)
    assert {:ok, "msg"} = open(t2, @key_b)

    assert {:error, :invalid} = open(t1, @key_b)
    assert {:error, :invalid} = open(t2, @key_a)
  end