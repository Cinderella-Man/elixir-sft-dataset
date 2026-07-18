defmodule AnonymizerTest do
  use ExUnit.Case, async: false

  describe "tokenize" do
    test "replaces listed fields with opaque tokens and returns a vault" do
      records = [%{id: 1, email: "a@x.com", name: "Al"}]
      {[r], vault} = Anonymizer.tokenize(records, [:email])
      assert r.id == 1
      assert r.name == "Al"
      assert is_binary(r.email)
      assert r.email != "a@x.com"
      assert r.email =~ ~r/^TOK_EMAIL_\d+$/
      assert is_map(vault)
    end

    test "referential integrity: same value maps to same token" do
      records = [%{email: "a@x.com"}, %{email: "a@x.com"}, %{email: "b@x.com"}]
      {[r1, r2, r3], _v} = Anonymizer.tokenize(records, [:email])
      assert r1.email == r2.email
      refute r1.email == r3.email
    end

    test "distinct fields get distinct token namespaces even for equal values" do
      records = [%{email: "same", user: "same"}]
      {[r], _v} = Anonymizer.tokenize(records, [:email, :user])
      refute r.email == r.user
      assert r.email =~ ~r/^TOK_EMAIL_/
      assert r.user =~ ~r/^TOK_USER_/
    end

    test "listed fields absent from a record are skipped" do
      records = [%{name: "Al"}]
      {[r], _v} = Anonymizer.tokenize(records, [:email])
      refute Map.has_key?(r, :email)
      assert r.name == "Al"
    end
  end

  describe "detokenize round trip" do
    test "restores original records exactly" do
      records = [
        %{id: 1, email: "a@x.com", ssn: "111"},
        %{id: 2, email: "a@x.com", ssn: "222"}
      ]

      {tokenized, vault} = Anonymizer.tokenize(records, [:email, :ssn])
      refute tokenized == records
      assert Anonymizer.detokenize(tokenized, vault) == records
    end

    test "values that are not known tokens are left untouched" do
      {_t, vault} = Anonymizer.tokenize([%{email: "a@x.com"}], [:email])
      records = [%{email: "not-a-token", age: 30}]
      assert Anonymizer.detokenize(records, vault) == records
    end
  end

  describe "edge cases" do
    test "empty record list tokenizes to empty list" do
      {recs, _v} = Anonymizer.tokenize([], [:email])
      assert recs == []
    end

    test "detokenize with an empty record list returns empty list" do
      {_t, vault} = Anonymizer.tokenize([%{email: "a@x.com"}], [:email])
      assert Anonymizer.detokenize([], vault) == []
    end
  end
end
