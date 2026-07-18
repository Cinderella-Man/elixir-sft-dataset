  test "string with no sensitive patterns is returned unchanged", %{m: m} do
    plain = "Hello, world! Nothing sensitive here."
    assert LogMasker.mask_string(m, plain) == plain
  end