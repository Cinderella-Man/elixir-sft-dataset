  test "hash is consistent for the same value", %{pid: pid} do
    [r1, r2] = Anonymizer.anonymize(pid, [%{email: "a@x.com"}, %{email: "a@x.com"}])
    assert r1.email == r2.email
  end