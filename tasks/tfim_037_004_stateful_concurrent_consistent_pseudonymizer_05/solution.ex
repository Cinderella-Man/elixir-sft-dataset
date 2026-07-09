  test "hash and redact rules work alongside pseudonyms", %{pid: pid} do
    [r] = Anonymizer.anonymize(pid, [%{name: "Alice", email: "a@x.com", ssn: "111"}])
    assert r.name =~ ~r/^PERSON_\d+$/
    assert r.email == :crypto.hash(:sha256, "a@x.com") |> Base.encode16(case: :lower)
    assert r.ssn == "[REDACTED]"
  end