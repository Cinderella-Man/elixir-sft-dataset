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

    test "counter starts at 1 and increments by 1 per newly seen value" do
      records = [%{email: "a@x.com"}, %{email: "b@x.com"}, %{email: "c@x.com"}]
      {[r1, r2, r3], _v} = Anonymizer.tokenize(records, [:email])
      assert r1.email == "TOK_EMAIL_1"
      assert r2.email == "TOK_EMAIL_2"
      assert r3.email == "TOK_EMAIL_3"
    end

    test "counter advances only on first sight of a value, not on repeats" do
      records = [
        %{email: "a@x.com"},
        %{email: "a@x.com"},
        %{email: "b@x.com"},
        %{email: "a@x.com"},
        %{email: "c@x.com"}
      ]

      {[r1, r2, r3, r4, r5], _v} = Anonymizer.tokenize(records, [:email])
      assert r1.email == "TOK_EMAIL_1"
      assert r2.email == "TOK_EMAIL_1"
      assert r3.email == "TOK_EMAIL_2"
      assert r4.email == "TOK_EMAIL_1"
      assert r5.email == "TOK_EMAIL_3"
    end

    test "each field counts from 1 independently in its own namespace" do
      records = [
        %{email: "e1", ssn: "s1"},
        %{email: "e2", ssn: "s1"},
        %{email: "e1", ssn: "s2"}
      ]

      {[r1, r2, r3], _v} = Anonymizer.tokenize(records, [:email, :ssn])
      assert r1.email == "TOK_EMAIL_1"
      assert r1.ssn == "TOK_SSN_1"
      assert r2.email == "TOK_EMAIL_2"
      assert r2.ssn == "TOK_SSN_1"
      assert r3.email == "TOK_EMAIL_1"
      assert r3.ssn == "TOK_SSN_2"
    end

    test "a repeated field is applied once, not as a second tokenization pass" do
      records = [%{email: "a@x.com"}, %{email: "b@x.com"}, %{email: "a@x.com"}]
      {once, _v1} = Anonymizer.tokenize(records, [:email])
      {twice, vault} = Anonymizer.tokenize(records, [:email, :email])

      # Listing :email twice yields exactly the single-mention result: no token
      # is fed back in and re-tokenized on the duplicate mention.
      assert twice == once
      assert Enum.map(twice, & &1.email) == ["TOK_EMAIL_1", "TOK_EMAIL_2", "TOK_EMAIL_1"]

      # The round trip stays lossless despite the duplicate field entry.
      assert Anonymizer.detokenize(twice, vault) == records
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

    test "literal tokens restore to the value their counter position names" do
      records = [%{email: "a@x.com"}, %{email: "b@x.com"}]
      {_t, vault} = Anonymizer.tokenize(records, [:email])

      assert Anonymizer.detokenize([%{email: "TOK_EMAIL_1"}], vault) ==
               [%{email: "a@x.com"}]

      assert Anonymizer.detokenize([%{email: "TOK_EMAIL_2"}], vault) ==
               [%{email: "b@x.com"}]
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
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
