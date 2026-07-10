  test "mask fully masks a 1-character string as *" do
    records = [%{user: %{initial: "Q"}}]
    [r] = Anonymizer.anonymize(records, %{"user.initial" => :mask})
    assert r.user.initial == "*"
  end