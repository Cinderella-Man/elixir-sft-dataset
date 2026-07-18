  test "applies strategies in keyword lists" do
    m = FieldMasker.new(%{password: :redact})
    result = FieldMasker.mask(m, username: "dave", password: "secret!")
    assert result[:username] == "dave"
    assert result[:password] == "[MASKED]"
  end