  test "mask/2 returns a pattern-free raw string unchanged", %{m: m} do
    plain = "Hello, world! Nothing sensitive here."
    assert LogMasker.mask(m, plain) == plain
  end