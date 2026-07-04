  test "referential integrity holds across separate batches", %{pid: pid} do
    [a] = Anonymizer.anonymize(pid, [%{name: "Alice"}])
    [b] = Anonymizer.anonymize(pid, [%{name: "Alice"}])
    assert a.name == b.name
  end