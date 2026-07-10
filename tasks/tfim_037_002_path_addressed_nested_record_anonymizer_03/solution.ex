  test "mask shows a 2-character string with no masking" do
    records = [%{user: %{code: "ab"}}]
    [r] = Anonymizer.anonymize(records, %{"user.code" => :mask})
    assert r.user.code == "ab"
  end