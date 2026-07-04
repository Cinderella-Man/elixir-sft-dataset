  test "pseudonyms follow prefix_N format and preserve referential integrity", %{pid: pid} do
    records = [%{name: "Alice"}, %{name: "Bob"}, %{name: "Alice"}]
    [r1, r2, r3] = Anonymizer.anonymize(pid, records)
    assert r1.name == r3.name
    refute r1.name == r2.name
    assert r1.name =~ ~r/^PERSON_\d+$/
    assert r2.name =~ ~r/^PERSON_\d+$/
  end