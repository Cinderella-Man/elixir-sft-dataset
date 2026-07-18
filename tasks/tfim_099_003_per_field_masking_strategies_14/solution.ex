  test "recursively applies strategies in nested maps" do
    m = FieldMasker.new(%{password: :redact})
    result = FieldMasker.mask(m, %{user: %{name: "carol", password: "deep"}})
    assert result.user.name == "carol"
    assert result.user.password == "[MASKED]"
  end