  test "hash strategy produces a deterministic sha256 hex digest" do
    m = FieldMasker.new(%{password: :hash})
    result = FieldMasker.mask(m, %{password: "hunter2"})
    expected = "sha256:" <> Base.encode16(:crypto.hash(:sha256, "hunter2"), case: :lower)
    assert result.password == expected
  end