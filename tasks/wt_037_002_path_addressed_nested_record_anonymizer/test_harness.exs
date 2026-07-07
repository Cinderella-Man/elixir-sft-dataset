defmodule AnonymizerTest do
  use ExUnit.Case, async: false

  defp sha256(v), do: :crypto.hash(:sha256, to_string(v)) |> Base.encode16(case: :lower)

  describe "nested path targeting" do
    test "hashes a value at a nested path and leaves siblings alone" do
      records = [%{id: 1, user: %{email: "a@x.com", name: "Al"}}]
      [r] = Anonymizer.anonymize(records, %{"user.email" => :hash})
      assert r.user.email == sha256("a@x.com")
      assert r.user.name == "Al"
      assert r.id == 1
    end

    test "redacts and masks at different nested paths" do
      records = [%{profile: %{ssn: "123-45-6789", first: "Jonathan"}}]
      [r] = Anonymizer.anonymize(records, %{"profile.ssn" => :redact, "profile.first" => :mask})
      assert r.profile.ssn == "[REDACTED]"
      assert r.profile.first == "J******n"
    end
  end

  describe "list descent with []" do
    test "applies a rule to a field of each element in a list" do
      records = [%{orders: [%{card: "1111"}, %{card: "2222"}]}]
      [r] = Anonymizer.anonymize(records, %{"orders[].card" => :redact})
      assert Enum.map(r.orders, & &1.card) == ["[REDACTED]", "[REDACTED]"]
    end

    test "hashes each scalar in a list of scalars (referential integrity within list)" do
      records = [%{tags: ["x", "y", "x"]}]
      [r] = Anonymizer.anonymize(records, %{"tags[]" => :hash})
      assert r.tags == [sha256("x"), sha256("y"), sha256("x")]
    end
  end

  describe "referential integrity" do
    test "same value at different paths and records yields identical output" do
      records = [
        %{user: %{email: "shared@x.com"}, backup: %{email: "shared@x.com"}},
        %{user: %{email: "shared@x.com"}, backup: %{email: "other@x.com"}}
      ]

      [r1, r2] = Anonymizer.anonymize(records, %{"user.email" => :hash, "backup.email" => :hash})
      assert r1.user.email == r1.backup.email
      assert r1.user.email == r2.user.email
      refute r2.user.email == r2.backup.email
    end

    test "deterministic fake preserves referential integrity across nesting" do
      records = [%{a: %{name: "Bob"}, b: %{name: "Bob"}}]
      [r] = Anonymizer.anonymize(records, %{"a.name" => {:fake, "s"}, "b.name" => {:fake, "s"}})
      assert r.a.name == r.b.name
      assert r.a.name != "Bob"
      assert is_binary(r.a.name)
    end
  end

  describe "edge cases" do
    test "missing path is ignored gracefully" do
      records = [%{user: %{name: "Alan"}}]
      [r] = Anonymizer.anonymize(records, %{"user.email" => :redact, "user.name" => :mask})
      assert r.user.name == "A**n"
      refute Map.has_key?(r.user, :email)
    end

    test "type mismatch along a path is skipped" do
      records = [%{user: "not-a-map"}]
      [r] = Anonymizer.anonymize(records, %{"user.email" => :redact})
      assert r.user == "not-a-map"
    end

    test "supports string-keyed maps" do
      records = [%{"user" => %{"email" => "a@x.com"}}]
      [r] = Anonymizer.anonymize(records, %{"user.email" => :hash})
      assert r["user"]["email"] == sha256("a@x.com")
    end

    test "empty record list returns empty list" do
      assert [] == Anonymizer.anonymize([], %{"a.b" => :hash})
    end
  end
end
