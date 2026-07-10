  test "mask keeps first and last characters of a 3-character string" do
    records = [%{user: %{tag: "abc"}}]
    [r] = Anonymizer.anonymize(records, %{"user.tag" => :mask})
    assert r.user.tag == "a*c"
  end