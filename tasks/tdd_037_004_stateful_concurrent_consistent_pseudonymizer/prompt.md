# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule AnonymizerTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} =
      Anonymizer.start_link(%{name: {:pseudonym, "PERSON"}, email: :hash, ssn: :redact})

    {:ok, pid: pid}
  end

  test "pseudonyms follow prefix_N format and preserve referential integrity", %{pid: pid} do
    records = [%{name: "Alice"}, %{name: "Bob"}, %{name: "Alice"}]
    [r1, r2, r3] = Anonymizer.anonymize(pid, records)
    assert r1.name == r3.name
    refute r1.name == r2.name
    assert r1.name =~ ~r/^PERSON_\d+$/
    assert r2.name =~ ~r/^PERSON_\d+$/
  end

  test "preserves record order under concurrent processing", %{pid: pid} do
    records = for i <- 1..50, do: %{name: "user#{i}", id: i}
    result = Anonymizer.anonymize(pid, records)
    assert Enum.map(result, & &1.id) == Enum.to_list(1..50)
  end

  test "referential integrity holds across separate batches", %{pid: pid} do
    [a] = Anonymizer.anonymize(pid, [%{name: "Alice"}])
    [b] = Anonymizer.anonymize(pid, [%{name: "Alice"}])
    assert a.name == b.name
  end

  test "hash and redact rules work alongside pseudonyms", %{pid: pid} do
    [r] = Anonymizer.anonymize(pid, [%{name: "Alice", email: "a@x.com", ssn: "111"}])
    assert r.name =~ ~r/^PERSON_\d+$/
    assert r.email == :crypto.hash(:sha256, "a@x.com") |> Base.encode16(case: :lower)
    assert r.ssn == "[REDACTED]"
  end

  test "hash is consistent for the same value", %{pid: pid} do
    [r1, r2] = Anonymizer.anonymize(pid, [%{email: "a@x.com"}, %{email: "a@x.com"}])
    assert r1.email == r2.email
  end

  test "distinct values get distinct pseudonyms under concurrent load", %{pid: pid} do
    records = for i <- 1..200, do: %{name: "name_#{i}"}
    result = Anonymizer.anonymize(pid, records)
    pseudonyms = Enum.map(result, & &1.name)
    assert length(Enum.uniq(pseudonyms)) == 200
  end

  test "mapping/2 exposes the value -> pseudonym table", %{pid: pid} do
    Anonymizer.anonymize(pid, [%{name: "Alice"}, %{name: "Bob"}])
    mapping = Anonymizer.mapping(pid, :name)
    assert map_size(mapping) == 2
    assert Map.has_key?(mapping, "Alice")
  end

  test "unlisted fields and missing rule fields are handled gracefully", %{pid: pid} do
    [r] = Anonymizer.anonymize(pid, [%{name: "Alice", role: "admin"}])
    assert r.role == "admin"
    assert r.name =~ ~r/^PERSON_\d+$/

    [r2] = Anonymizer.anonymize(pid, [%{email: "a@x.com"}])
    assert Map.has_key?(r2, :email)
  end

  test "distinct non-string and string values are not conflated into one pseudonym", %{pid: pid} do
    [r1, r2, r3] = Anonymizer.anonymize(pid, [%{name: 42}, %{name: "42"}, %{name: 42}])
    assert r1.name == r3.name
    refute r1.name == r2.name
    assert map_size(Anonymizer.mapping(pid, :name)) == 2
  end

  test "mapping/2 keys are the original values, not stringified copies", %{pid: pid} do
    Anonymizer.anonymize(pid, [%{name: 42}])
    mapping = Anonymizer.mapping(pid, :name)
    assert Map.has_key?(mapping, 42)
    assert mapping[42] =~ ~r/^PERSON_\d+$/
  end

  test "each pseudonymized field numbers independently with its own prefix" do
    {:ok, pid} = Anonymizer.start_link(%{name: {:pseudonym, "PERSON"}, org: {:pseudonym, "ORG"}})
    [r] = Anonymizer.anonymize(pid, [%{name: "Acme", org: "Acme"}])
    assert r.name == "PERSON_1"
    assert r.org == "ORG_1"
    assert Anonymizer.mapping(pid, :name) == %{"Acme" => "PERSON_1"}
    assert Anonymizer.mapping(pid, :org) == %{"Acme" => "ORG_1"}
  end

  test "records missing rule fields do not gain those keys", %{pid: pid} do
    [r] = Anonymizer.anonymize(pid, [%{role: "admin"}])
    assert r == %{role: "admin"}
    refute Map.has_key?(r, :name)
    refute Map.has_key?(r, :email)
    refute Map.has_key?(r, :ssn)
  end

  test "mapping/2 accumulates entries across separate anonymize calls", %{pid: pid} do
    Anonymizer.anonymize(pid, [%{name: "Alice"}])
    Anonymizer.anonymize(pid, [%{name: "Bob"}, %{name: "Alice"}])
    mapping = Anonymizer.mapping(pid, :name)
    assert map_size(mapping) == 2
    assert Map.has_key?(mapping, "Alice")
    assert Map.has_key?(mapping, "Bob")
    assert length(Enum.uniq(Map.values(mapping))) == 2
  end

  test "start_link/1 returns {:ok, pid} for a rules map" do
    assert {:ok, pid} = Anonymizer.start_link(%{name: {:pseudonym, "P"}})
    assert is_pid(pid)
    assert Process.alive?(pid)
    assert Anonymizer.mapping(pid, :name) == %{}
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
