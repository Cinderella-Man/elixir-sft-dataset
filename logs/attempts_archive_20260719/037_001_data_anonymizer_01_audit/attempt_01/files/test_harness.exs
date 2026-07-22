defmodule AnonymizerTest do
  use ExUnit.Case, async: true

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  # Independent copies of the word lists documented in Anonymizer's @moduledoc.
  @first_names ~w(
    Alice Bob Carol Dave Eve Frank Grace Henry Iris Jack
    Karen Leo Maya Noah Olivia Paul Quinn Rose Sam Tara
    Uma Victor Wendy Xander Yara Zoe Adrian Blair Casey
    Dana Elliot Faye Glenn Harper Indira Jules
  )

  @last_names ~w(
    Smith Jones Williams Brown Taylor Davies Evans Wilson
    Thomas Roberts Johnson Lee Walker Hall Allen Young
    Hernandez King Wright Scott Baker Green Adams Nelson
    Carter Mitchell Perez Turner Campbell Parker Edwards
  )

  @domains ~w(
    example.com mail.net webhost.org fakemail.io testdomain.com
    inbox.dev sample.org placeholder.net demo.io fictitious.com
  )

  defp sha256(value) do
    :crypto.hash(:sha256, to_string(value)) |> Base.encode16(case: :lower)
  end

  # Mirror of the derivation documented in Anonymizer's @moduledoc. Written
  # independently of the implementation so that any behavioural drift in the
  # generator (byte usage, index arithmetic, format selection, suffix ranges)
  # is caught here.
  defp expected_fake(value, seed) do
    <<b0, b1, b2, b3, b4, b5, b6, _rest::binary>> =
      :crypto.hash(:sha256, "#{inspect(seed)}:#{to_string(value)}")

    first = Enum.at(@first_names, rem(b0, length(@first_names)))
    last = Enum.at(@last_names, rem(b1, length(@last_names)))

    case rem(b2, 4) do
      0 ->
        "#{first} #{last}"

      1 ->
        domain = Enum.at(@domains, rem(b3, length(@domains)))
        "#{String.downcase(first)}.#{String.downcase(last)}@#{domain}"

      2 ->
        "#{first}#{rem(b3 * 256 + b4, 9000) + 1000}"

      3 ->
        "#{String.downcase(first)}-#{String.downcase(last)}-#{rem(b5 * 256 + b6, 90) + 10}"
    end
  end

  defp fake_values(values, seed) do
    values
    |> Enum.map(&%{name: &1})
    |> Anonymizer.anonymize(%{name: {:fake, seed}})
    |> Enum.map(& &1.name)
  end

  defp sample_values(n), do: Enum.map(1..n, &"person-#{&1}@corp.example")

  defp classify(fake) do
    cond do
      Regex.match?(~r/^[A-Z][a-z]+ [A-Z][a-z]+$/, fake) -> :full_name
      Regex.match?(~r/^[a-z]+\.[a-z]+@[a-z]+\.[a-z]+$/, fake) -> :email
      Regex.match?(~r/^[A-Z][a-z]+\d{4}$/, fake) -> :name_with_number
      Regex.match?(~r/^[a-z]+-[a-z]+-\d{2}$/, fake) -> :handle
      true -> :unknown
    end
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

    test "empty string is returned unchanged" do
      [result] = Anonymizer.anonymize([%{name: ""}], %{name: :mask})
      assert result.name == ""
    end

    test "mask length equals input length for every string length from 1 to 12" do
      values = Enum.map(1..12, fn n -> String.duplicate("a", n - 1) <> "z" end)
      records = Enum.map(values, &%{name: &1})
      results = Anonymizer.anonymize(records, %{name: :mask})

      Enum.zip(values, results)
      |> Enum.each(fn {value, result} ->
        assert String.length(result.name) == String.length(value)
      end)
    end

    test "outer characters are preserved exactly for a long string" do
      [result] = Anonymizer.anonymize([%{name: "abcdefghij"}], %{name: :mask})
      assert result.name == "a********j"
      assert String.first(result.name) == "a"
      assert String.last(result.name) == "j"
    end

    test "distinct first and last characters both survive masking" do
      [r1, r2] = Anonymizer.anonymize([%{v: "start"}, %{v: "stark"}], %{v: :mask})
      assert r1.v == "s***t"
      assert r2.v == "s***k"
      refute r1.v == r2.v
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
  # {:fake, seed} — documented derivation
  # -------------------------------------------------------

  describe "{:fake, seed} documented derivation" do
    test "every fake matches the documented byte-driven derivation, for many seeds" do
      values = sample_values(300)

      for seed <- ["s1", "another-seed", :atom_seed, 42] do
        expected = Enum.map(values, &expected_fake(&1, seed))
        assert fake_values(values, seed) == expected
      end
    end

    test "all four documented output formats occur across a large value set" do
      shapes =
        sample_values(400)
        |> fake_values("format-coverage")
        |> Enum.map(&classify/1)

      assert :unknown not in shapes

      counts = Enum.frequencies(shapes)

      for shape <- [:full_name, :email, :name_with_number, :handle] do
        assert Map.get(counts, shape, 0) > 0, "format #{shape} never produced"
      end
    end

    test "numeric suffixes stay inside their documented ranges" do
      fakes = fake_values(sample_values(400), "suffix-ranges")

      four_digit =
        for f <- fakes, classify(f) == :name_with_number do
          f |> String.replace(~r/^[A-Za-z]+/, "") |> String.to_integer()
        end

      two_digit =
        for f <- fakes, classify(f) == :handle do
          f |> String.split("-") |> List.last() |> String.to_integer()
        end

      assert four_digit != []
      assert two_digit != []
      assert Enum.all?(four_digit, &(&1 >= 1000 and &1 <= 9999))
      assert Enum.all?(two_digit, &(&1 >= 10 and &1 <= 99))
    end

    test "name and domain parts always come from the documented word lists" do
      lower_first = Enum.map(@first_names, &String.downcase/1)
      lower_last = Enum.map(@last_names, &String.downcase/1)

      sample_values(400)
      |> fake_values("word-lists")
      |> Enum.each(fn fake ->
        case classify(fake) do
          :full_name ->
            [f, l] = String.split(fake, " ")
            assert f in @first_names
            assert l in @last_names

          :email ->
            [local, domain] = String.split(fake, "@")
            [f, l] = String.split(local, ".")
            assert f in lower_first
            assert l in lower_last
            assert domain in @domains

          :name_with_number ->
            assert String.replace(fake, ~r/\d+$/, "") in @first_names

          :handle ->
            [f, l, _n] = String.split(fake, "-")
            assert f in lower_first
            assert l in lower_last

          :unknown ->
            flunk("unrecognised fake format: #{inspect(fake)}")
        end
      end)
    end

    test "generator spreads across the whole word lists, not a narrow prefix" do
      fakes = fake_values(sample_values(600), "spread")

      firsts =
        for f <- fakes, classify(f) == :full_name, do: f |> String.split(" ") |> hd()

      lasts =
        for f <- fakes, classify(f) == :full_name, do: f |> String.split(" ") |> List.last()

      domains =
        for f <- fakes, classify(f) == :email, do: f |> String.split("@") |> List.last()

      assert Enum.uniq(firsts) |> length() > 20
      assert Enum.uniq(lasts) |> length() > 20
      assert Enum.uniq(domains) |> length() > 5
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
