  test "mapping/2 exposes the value -> pseudonym table", %{pid: pid} do
    Anonymizer.anonymize(pid, [%{name: "Alice"}, %{name: "Bob"}])
    mapping = Anonymizer.mapping(pid, :name)
    assert map_size(mapping) == 2
    assert Map.has_key?(mapping, "Alice")
  end