  test "mapping/2 accumulates entries across separate anonymize calls", %{pid: pid} do
    Anonymizer.anonymize(pid, [%{name: "Alice"}])
    Anonymizer.anonymize(pid, [%{name: "Bob"}, %{name: "Alice"}])
    mapping = Anonymizer.mapping(pid, :name)
    assert map_size(mapping) == 2
    assert Map.has_key?(mapping, "Alice")
    assert Map.has_key?(mapping, "Bob")
    assert length(Enum.uniq(Map.values(mapping))) == 2
  end