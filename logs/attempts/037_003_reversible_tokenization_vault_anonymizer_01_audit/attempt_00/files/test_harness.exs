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

  test "round trip is lossless when an unlisted field already holds a token-shaped string" do
    # :note is never listed, so tokenize/2 leaves its literal "TOK_EMAIL_1" alone.
    # detokenize/2 must still hand back the original records unchanged.
    records = [%{email: "a@x.com", note: "TOK_EMAIL_1"}]
    {tokenized, vault} = Anonymizer.tokenize(records, [:email])

    assert Enum.map(tokenized, & &1.note) == ["TOK_EMAIL_1"]
    assert Anonymizer.detokenize(tokenized, vault) == records
  end

  test "an empty field list leaves every record completely untouched" do
    records = [%{id: 1, email: "a@x.com"}, %{id: 2, email: "b@x.com"}]
    {tokenized, vault} = Anonymizer.tokenize(records, [])

    assert tokenized == records
    assert Anonymizer.detokenize(tokenized, vault) == records
  end

  test "non-binary originals are tokenized by value equality and restored losslessly" do
    records = [
      %{age: 30, meta: %{a: 1}},
      %{age: 30, meta: %{a: 1}},
      %{age: 31, meta: %{a: 2}}
    ]

    {[r1, r2, r3] = tokenized, vault} = Anonymizer.tokenize(records, [:age, :meta])

    assert is_binary(r1.age)
    assert is_binary(r1.meta)
    assert r1.age == r2.age
    assert r1.meta == r2.meta
    refute r1.age == r3.age
    refute r1.meta == r3.meta
    assert Anonymizer.detokenize(tokenized, vault) == records
  end

  test "a known token is restored wherever it appears, including in a never-listed field" do
    {_t, vault} = Anonymizer.tokenize([%{email: "a@x.com"}], [:email])

    assert Anonymizer.detokenize([%{audit_note: "TOK_EMAIL_1", id: 7}], vault) ==
             [%{audit_note: "a@x.com", id: 7}]
  end

  test "token-shaped strings the vault never issued survive detokenize unchanged" do
    {_t, vault} = Anonymizer.tokenize([%{email: "a@x.com"}], [:email])

    records = [%{email: "TOK_EMAIL_99", other: "TOK_SSN_1", n: 1, nope: nil}]
    assert Anonymizer.detokenize(records, vault) == records
  end

  test "multi-word field names are uppercased wholesale in the token namespace" do
    records = [%{user_email: "a@x.com"}, %{user_email: "b@x.com"}]
    {[r1, r2] = tokenized, vault} = Anonymizer.tokenize(records, [:user_email])

    assert r1.user_email == "TOK_USER_EMAIL_1"
    assert r2.user_email == "TOK_USER_EMAIL_2"
    assert Anonymizer.detokenize(tokenized, vault) == records
  end
end
