defmodule AnonymizerTest do
  use ExUnit.Case, async: true

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  defp sha256(value) do
    :crypto.hash(:sha256, to_string(value)) |> Base.encode16(case: :lower)
  end

  # -------------------------------------------------------
  # :hash rule
  # -------------------------------------------------------

  describe ":hash" do
    test "replaces value with its SHA-256 hex digest" do
      [result] = Anonymizer.anonymize([%{email: "alice@example.com"}], %{email: :hash})
      assert result.email == sha256("alice@example.com")
    end

    test "referential integrity: same value produces same hash across records" do
      records = [
        %{id: 1, email: "shared@example.com"},
        %{id: 2, email: "shared@example.com"}
      ]

      [r1, r2] = Anonymizer.anonymize(records, %{email: :hash})
      assert r1.email == r2.email
    end

    test "different values produce different hashes" do
      records = [%{email: "a@example.com"}, %{email: "b@example.com"}]
      [r1, r2] = Anonymizer.anonymize(records, %{email: :hash})
      refute r1.email == r2.email
    end
  end

  # -------------------------------------------------------
  # :mask rule
  # -------------------------------------------------------

  describe ":mask" do
    test "keeps first and last character, replaces middle with asterisks" do
      [result] = Anonymizer.anonymize([%{name: "Jonathan"}], %{name: :mask})
      assert result.name == "J******n"
    end

    test "two-character string shows both characters unmasked" do
      [result] = Anonymizer.anonymize([%{name: "Jo"}], %{name: :mask})
      assert result.name == "Jo"
    end

    test "single-character string is fully masked" do
      [result] = Anonymizer.anonymize([%{name: "X"}], %{name: :mask})
      assert result.name == "*"
    end

    test "masked output cannot trivially reveal the original value" do
      original = "secretpassword"
      [result] = Anonymizer.anonymize([%{val: original}], %{val: :mask})
      # Middle characters must all be asterisks — originals are gone
      inner = result.val |> String.slice(1..-2//1)
      assert String.match?(inner, ~r/^\*+$/)
    end

    test "referential integrity: same value produces same mask" do
      records = [%{name: "Alice"}, %{name: "Alice"}]
      [r1, r2] = Anonymizer.anonymize(records, %{name: :mask})
      assert r1.name == r2.name
    end
  end

  # -------------------------------------------------------
  # :redact rule
  # -------------------------------------------------------

  describe ":redact" do
    test "replaces value with [REDACTED]" do
      [result] = Anonymizer.anonymize([%{ssn: "123-45-6789"}], %{ssn: :redact})
      assert result.ssn == "[REDACTED]"
    end

    test "all values for a redacted field become [REDACTED] regardless of input" do
      records = [%{ssn: "111-11-1111"}, %{ssn: "999-99-9999"}]
      [r1, r2] = Anonymizer.anonymize(records, %{ssn: :redact})
      assert r1.ssn == "[REDACTED]"
      assert r2.ssn == "[REDACTED]"
    end
  end

  # -------------------------------------------------------
  # {:fake, seed} rule
  # -------------------------------------------------------

  describe "{:fake, seed}" do
    test "returns a non-empty string different from the original" do
      [result] = Anonymizer.anonymize([%{name: "Alice"}], %{name: {:fake, "seed1"}})
      assert is_binary(result.name)
      assert result.name != ""
      assert result.name != "Alice"
    end

    test "deterministic: same value + seed always produces the same fake" do
      rules = %{name: {:fake, "myseed"}}
      [r1] = Anonymizer.anonymize([%{name: "Alice"}], rules)
      [r2] = Anonymizer.anonymize([%{name: "Alice"}], rules)
      assert r1.name == r2.name
    end

    test "referential integrity: same value maps to same fake across records in one call" do
      records = [%{id: 1, name: "Bob"}, %{id: 2, name: "Bob"}]
      [r1, r2] = Anonymizer.anonymize(records, %{name: {:fake, "s"}})
      assert r1.name == r2.name
    end

    test "different seeds produce different fakes for the same value" do
      [r1] = Anonymizer.anonymize([%{name: "Alice"}], %{name: {:fake, "seed_a"}})
      [r2] = Anonymizer.anonymize([%{name: "Alice"}], %{name: {:fake, "seed_b"}})
      refute r1.name == r2.name
    end

    test "different input values produce different fakes with the same seed" do
      records = [%{name: "Alice"}, %{name: "Bob"}]
      [r1, r2] = Anonymizer.anonymize(records, %{name: {:fake, "same_seed"}})
      refute r1.name == r2.name
    end
  end

  # -------------------------------------------------------
  # Field independence and passthrough
  # -------------------------------------------------------

  describe "field handling" do
    test "untouched fields are passed through unchanged" do
      records = [%{email: "alice@example.com", age: 30, role: "admin"}]
      [result] = Anonymizer.anonymize(records, %{email: :redact})
      assert result.age == 30
      assert result.role == "admin"
    end

    test "multiple rules applied in the same call" do
      record = %{email: "alice@example.com", name: "Alice", ssn: "123-45-6789"}
      [result] = Anonymizer.anonymize([record], %{email: :hash, name: :mask, ssn: :redact})

      assert result.email == sha256("alice@example.com")
      assert result.name == "A***e"
      assert result.ssn == "[REDACTED]"
    end

    test "different fields can use different rules independently" do
      records = [
        %{email: "a@x.com", name: "Alice"},
        %{email: "a@x.com", name: "Bob"}
      ]

      [r1, r2] = Anonymizer.anonymize(records, %{email: :hash, name: :mask})

      # Same email → same hash (referential integrity)
      assert r1.email == r2.email

      # Different names → different masks
      refute r1.name == r2.name
    end
  end

  # -------------------------------------------------------
  # Empty and edge cases
  # -------------------------------------------------------

  describe "edge cases" do
    test "empty record list returns empty list" do
      assert [] == Anonymizer.anonymize([], %{email: :hash})
    end

    test "empty rules map leaves all records unchanged" do
      records = [%{email: "alice@example.com", age: 30}]
      assert records == Anonymizer.anonymize(records, %{})
    end

    test "rule for a field not present in a record is ignored gracefully" do
      records = [%{name: "Alice"}]
      # :email rule present but record has no :email key
      result = Anonymizer.anonymize(records, %{email: :redact, name: :mask})
      [r] = result
      assert r.name == "A***e"
      refute Map.has_key?(r, :email)
    end
  end

  test "fake value depends only on value and seed, not on position or neighbouring records" do
    rules = %{name: {:fake, "s1"}}

    [alone] = Anonymizer.anonymize([%{name: "Bob"}], rules)

    batch =
      Anonymizer.anonymize(
        [
          %{name: "Zed", extra: "noise"},
          %{name: "Alice"},
          %{name: "Bob", extra: 99},
          %{name: "Carol"}
        ],
        rules
      )

    in_batch = Enum.at(batch, 2)
    assert in_batch.name == alone.name

    [first_of_two] = Anonymizer.anonymize([%{name: "Bob", other: :ignored}], rules)
    assert first_of_two.name == alone.name
  end

  test "returned list preserves length, order and the exact key set of every record" do
    records = [
      %{id: 1, name: "Alice", age: 30},
      %{id: 2, name: "Alice", age: 31},
      %{id: 3, name: "Bo", age: 32},
      %{id: 4, name: "X", age: 33}
    ]

    results = Anonymizer.anonymize(records, %{name: :mask})

    assert length(results) == length(records)
    assert Enum.map(results, & &1.id) == [1, 2, 3, 4]

    Enum.zip(records, results)
    |> Enum.each(fn {original, result} ->
      assert Map.keys(result) |> Enum.sort() == Map.keys(original) |> Enum.sort()
      assert result.age == original.age
    end)

    assert Enum.map(results, & &1.name) == ["A***e", "A***e", "Bo", "*"]
  end

  test "referential integrity holds simultaneously for hash, mask, redact and fake rules" do
    records = [
      %{h: "dup", m: "dup", r: "dup", f: "dup"},
      %{h: "other", m: "other", r: "other", f: "other"},
      %{h: "dup", m: "dup", r: "dup", f: "dup"}
    ]

    rules = %{h: :hash, m: :mask, r: :redact, f: {:fake, "seed"}}
    [r1, r2, r3] = Anonymizer.anonymize(records, rules)

    assert r1.h == r3.h
    assert r1.m == r3.m
    assert r1.r == r3.r
    assert r1.f == r3.f

    refute r1.h == r2.h
    refute r1.f == r2.f
  end

  test "three-character string keeps outer characters and masks exactly one middle character" do
    [result] = Anonymizer.anonymize([%{name: "Bob"}], %{name: :mask})
    assert result.name == "B*b"
  end
end
