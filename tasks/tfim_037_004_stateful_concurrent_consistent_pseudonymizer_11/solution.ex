  test "each pseudonymized field numbers independently with its own prefix" do
    {:ok, pid} = Anonymizer.start_link(%{name: {:pseudonym, "PERSON"}, org: {:pseudonym, "ORG"}})
    [r] = Anonymizer.anonymize(pid, [%{name: "Acme", org: "Acme"}])
    assert r.name == "PERSON_1"
    assert r.org == "ORG_1"
    assert Anonymizer.mapping(pid, :name) == %{"Acme" => "PERSON_1"}
    assert Anonymizer.mapping(pid, :org) == %{"Acme" => "ORG_1"}
  end