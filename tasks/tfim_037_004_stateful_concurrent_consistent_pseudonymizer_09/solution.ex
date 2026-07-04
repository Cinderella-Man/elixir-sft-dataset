  test "unlisted fields and missing rule fields are handled gracefully", %{pid: pid} do
    [r] = Anonymizer.anonymize(pid, [%{name: "Alice", role: "admin"}])
    assert r.role == "admin"
    assert r.name =~ ~r/^PERSON_\d+$/

    [r2] = Anonymizer.anonymize(pid, [%{email: "a@x.com"}])
    assert Map.has_key?(r2, :email)
  end