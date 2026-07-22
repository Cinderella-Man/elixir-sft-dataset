Code.require_file("solution.ex", __DIR__)

defmodule DataQualityScorerTest do
  use ExUnit.Case, async: false

  defp assert_score(actual, expected) do
    assert_in_delta(actual, expected, 0.01)
  end

  # -------------------------------------------------------
  # Comprehensive dataset with known quality issues
  # -------------------------------------------------------

  defp comprehensive_rules do
    %{
      id: [:not_null, :unique],
      email: [:not_null, {:format, ~r/^[^@\s]+@[^@\s]+$/}],
      age: [{:range, 0, 120}],
      country: [{:referential, MapSet.new(["US", "UK", "CA"])}]
    }
  end

  defp comprehensive_records do
    [
      # R1: everything passes
      %{id: 1, email: "a@b.com", age: 30, country: "US"},
      # R2: bad email format, age out of range
      %{id: 2, email: "bad-email", age: 200, country: "US"},
      # R3: duplicate id (fails unique), country not referential
      %{id: 2, email: "c@d.com", age: 25, country: "FR"},
      # R4: email nil (fails not_null + format)
      %{id: 4, email: nil, age: 40, country: "UK"},
      # R5: email key missing
      %{id: 5, age: 50, country: "CA"}
    ]
  end

  test "per-record scores match expectations" do
    result = DataQualityScorer.score(comprehensive_records(), comprehensive_rules())
    records = result.records

    assert length(records) == 5

    [r1, r2, r3, r4, r5] = records

    # total is constant: 2 + 2 + 1 + 1 = 6
    assert Enum.all?(records, &(&1.total == 6))

    assert r1.passed == 6
    assert_score(r1.score, 100.0)

    assert r2.passed == 4
    assert_score(r2.score, 66.6667)

    assert r3.passed == 4
    assert_score(r3.score, 66.6667)

    assert r4.passed == 4
    assert_score(r4.score, 66.6667)

    assert r5.passed == 4
    assert_score(r5.score, 66.6667)
  end

  test "per-field scores match expectations" do
    result = DataQualityScorer.score(comprehensive_records(), comprehensive_rules())
    fields = result.fields

    # id: R1, R4, R5 pass (R2/R3 share id 2 -> fail unique) => 3/5
    assert_score(fields.id, 60.0)
    # email: only R1 and R3 pass => 2/5
    assert_score(fields.email, 40.0)
    # age: all except R2 (200) => 4/5
    assert_score(fields.age, 80.0)
    # country: all except R3 (FR) => 4/5
    assert_score(fields.country, 80.0)
  end

  test "overall score matches expectations" do
    result = DataQualityScorer.score(comprehensive_records(), comprehensive_rules())
    # total passed = 6 + 4 + 4 + 4 + 4 = 22 out of 5 * 6 = 30
    assert_score(result.overall, 73.3333)
  end

  test "records are returned in input order" do
    rules = %{id: [:not_null]}
    records = [%{id: 9}, %{id: 3}, %{id: 7}]
    result = DataQualityScorer.score(records, rules)
    assert Enum.map(result.records, & &1.passed) == [1, 1, 1]
    assert length(result.records) == 3
  end

  # -------------------------------------------------------
  # :not_null
  # -------------------------------------------------------

  test "not_null fails for both nil values and missing keys" do
    rules = %{a: [:not_null]}
    records = [%{a: 1}, %{a: nil}, %{}]
    result = DataQualityScorer.score(records, rules)

    [r1, r2, r3] = result.records
    assert r1.passed == 1
    assert r2.passed == 0
    assert r3.passed == 0

    # 1 of 3 records passes the field
    assert_score(result.fields.a, 33.3333)
  end

  # -------------------------------------------------------
  # :unique
  # -------------------------------------------------------

  test "unique passes only for values appearing exactly once" do
    rules = %{a: [:unique]}
    records = [%{a: 1}, %{a: 2}, %{a: 2}, %{a: 3}]
    result = DataQualityScorer.score(records, rules)

    passed = Enum.map(result.records, & &1.passed)
    # 1 -> unique, 2 -> dup, 2 -> dup, 3 -> unique
    assert passed == [1, 0, 0, 1]
    assert_score(result.fields.a, 50.0)
  end

  test "unique treats repeated nil (including missing keys) as duplicates" do
    rules = %{a: [:unique]}
    records = [%{a: nil}, %{}, %{a: 7}]
    result = DataQualityScorer.score(records, rules)

    passed = Enum.map(result.records, & &1.passed)
    # nil appears twice (explicit nil + missing key), 7 once
    assert passed == [0, 0, 1]
    assert_score(result.fields.a, 33.3333)
  end

  # -------------------------------------------------------
  # :format
  # -------------------------------------------------------

  test "format matches strings and rejects non-strings and nil" do
    rules = %{a: [{:format, ~r/^\d+$/}]}
    records = [%{a: "123"}, %{a: "12a"}, %{a: 5}, %{a: nil}, %{}]
    result = DataQualityScorer.score(records, rules)

    passed = Enum.map(result.records, & &1.passed)
    assert passed == [1, 0, 0, 0, 0]
    assert_score(result.fields.a, 20.0)
  end

  # -------------------------------------------------------
  # :range
  # -------------------------------------------------------

  test "range is inclusive and rejects non-numbers and nil" do
    rules = %{a: [{:range, 10, 20}]}

    records = [
      %{a: 10},
      %{a: 20},
      %{a: 9},
      %{a: 21},
      %{a: 15.5},
      %{a: "x"},
      %{a: nil}
    ]

    result = DataQualityScorer.score(records, rules)

    passed = Enum.map(result.records, & &1.passed)
    # 10 ok, 20 ok, 9 no, 21 no, 15.5 ok, "x" no, nil no
    assert passed == [1, 1, 0, 0, 1, 0, 0]
    assert_score(result.fields.a, 42.8571)
  end

  # -------------------------------------------------------
  # :referential
  # -------------------------------------------------------

  test "referential passes only for members of the provided set" do
    set = MapSet.new([:a, :b])
    rules = %{c: [{:referential, set}]}
    records = [%{c: :a}, %{c: :b}, %{c: :z}, %{c: nil}]
    result = DataQualityScorer.score(records, rules)

    passed = Enum.map(result.records, & &1.passed)
    assert passed == [1, 1, 0, 0]
    assert_score(result.fields.c, 50.0)
  end

  # -------------------------------------------------------
  # A record that passes everything scores 100
  # -------------------------------------------------------

  test "record passing all rules scores 100" do
    rules = %{
      id: [:not_null, :unique],
      name: [:not_null, {:format, ~r/^[A-Z][a-z]+$/}],
      score: [{:range, 0, 100}]
    }

    records = [%{id: 1, name: "Ada", score: 99}]
    result = DataQualityScorer.score(records, rules)

    [r1] = result.records
    assert r1.total == 4
    assert r1.passed == 4
    assert_score(r1.score, 100.0)
    assert_score(result.overall, 100.0)
    assert_score(result.fields.id, 100.0)
    assert_score(result.fields.name, 100.0)
    assert_score(result.fields.score, 100.0)
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "empty dataset yields vacuous 100 scores" do
    rules = %{id: [:not_null], email: [{:format, ~r/@/}]}
    result = DataQualityScorer.score([], rules)

    assert result.records == []
    assert_score(result.overall, 100.0)
    assert_score(result.fields.id, 100.0)
    assert_score(result.fields.email, 100.0)
  end

  test "no rules at all yields 100 for every record and overall" do
    rules = %{}
    records = [%{a: 1}, %{a: 2}]
    result = DataQualityScorer.score(records, rules)

    assert Enum.all?(result.records, &(&1.total == 0))
    assert Enum.all?(result.records, &(&1.passed == 0))
    Enum.each(result.records, fn r -> assert_score(r.score, 100.0) end)
    assert_score(result.overall, 100.0)
    assert result.fields == %{}
  end

  test "single field with multiple rules counts each rule individually" do
    rules = %{email: [:not_null, {:format, ~r/@/}]}
    records = [
      %{email: "a@b"},
      %{email: "bad"},
      %{email: nil}
    ]

    result = DataQualityScorer.score(records, rules)
    [r1, r2, r3] = result.records

    assert r1.total == 2 and r1.passed == 2
    assert r2.total == 2 and r2.passed == 1
    assert r3.total == 2 and r3.passed == 0

    # field passes only when ALL its rules pass -> only R1
    assert_score(result.fields.email, 33.3333)
    # overall = (2 + 1 + 0) / (3 * 2) = 3/6
    assert_score(result.overall, 50.0)
  end
end