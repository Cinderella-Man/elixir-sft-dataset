  test "sealing the same payload twice yields different tokens (random nonce)" do
    t1 = seal("same", @key, 60)
    t2 = seal("same", @key, 60)
    refute t1 == t2
    assert {:ok, "same"} = open(t1, @key)
    assert {:ok, "same"} = open(t2, @key)
  end