# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

```elixir
defmodule Anonymizer do
  @moduledoc """
  Anonymizes specified fields in a list of record maps according to configurable rules.

  Supported rules (values in the `rules` map):

    * `:hash`         – Replace the value with its SHA-256 hex digest.
    * `:mask`         – Keep the first and last character; replace every middle
                        character with `*`. A 2-character string is left as-is.
                        A 1-character string becomes `"*"`.
    * `:redact`       – Replace the value with the string `"[REDACTED]"`.
    * `{:fake, seed}` – Produce a deterministic, realistic-looking fake value
                        derived from the original value and the given seed.
                        The same (value, seed) pair always yields the same output.

  Referential integrity is guaranteed across the entire list: because every rule
  is a pure function of its inputs, two records that share the same original
  value for a field will always receive the same anonymized output.

  Only OTP/stdlib modules are used (`:crypto`, `Base`, `String`, `Enum`, `Map`).
  """

  @typedoc "A single anonymisation rule."
  @type rule :: :hash | :mask | :redact | {:fake, term()}

  # ---------------------------------------------------------------------------
  # Word lists for deterministic fake-value generation
  # ---------------------------------------------------------------------------

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

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Anonymizes `records` in accordance with `rules`.

  ## Parameters

    * `records` – a list of maps (each map represents one record).
    * `rules`   – a map whose keys are field-name atoms and whose values are
                  rule atoms or tuples (see module doc for supported rules).

  ## Returns

  A list of maps of the same length and structure as `records`. Fields named
  in `rules` are transformed; all other fields are left untouched. If a record
  does not contain a field named in `rules`, that entry is silently skipped.

  ## Examples

      iex> records = [
      ...>   %{name: "Alice", email: "alice@example.com", age: 30},
      ...>   %{name: "Bob",   email: "bob@example.com",   age: 25},
      ...>   %{name: "Alice", email: "alice@example.com", age: 42},
      ...> ]
      iex> rules = %{name: :mask, email: :redact}
      iex> Anonymizer.anonymize(records, rules)
      [
        %{name: "A***e", email: "[REDACTED]", age: 30},
        %{name: "B*b",   email: "[REDACTED]", age: 25},
        %{name: "A***e", email: "[REDACTED]", age: 42}
      ]

  Note that both records with `name: "Alice"` produce the same masked output,
  demonstrating referential integrity.
  """
  @spec anonymize([map()], %{atom() => rule()}) :: [map()]
  def anonymize(records, rules) when is_list(records) and is_map(rules) do
    Enum.map(records, &anonymize_record(&1, rules))
  end

  # ---------------------------------------------------------------------------
  # Private – per-record transformation
  # ---------------------------------------------------------------------------

  defp anonymize_record(record, rules) do
    Enum.reduce(rules, record, fn {field, rule}, acc ->
      case Map.fetch(acc, field) do
        {:ok, value} -> Map.put(acc, field, apply_rule(value, rule))
        :error -> acc
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Private – rule dispatch
  # ---------------------------------------------------------------------------

  # :redact ----------------------------------------------------------------
  defp apply_rule(_value, :redact), do: "[REDACTED]"

  # :hash ------------------------------------------------------------------
  defp apply_rule(value, :hash) do
    value
    |> to_string()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  # :mask ------------------------------------------------------------------
  defp apply_rule(value, :mask) do
    str = to_string(value)

    case String.length(str) do
      0 ->
        str

      1 ->
        "*"

      2 ->
        str

      len ->
        first = String.at(str, 0)
        last = String.at(str, len - 1)
        middle = String.duplicate("*", len - 2)
        first <> middle <> last
    end
  end

  # {:fake, seed} ----------------------------------------------------------
  defp apply_rule(value, {:fake, seed}) do
    generate_fake(to_string(value), seed)
  end

  # ---------------------------------------------------------------------------
  # Private – deterministic fake-value generator
  #
  # Strategy: hash "#{inspect(seed)}:#{value}" with SHA-256, then use successive
  # bytes as indices into word-lists / number ranges to assemble a
  # realistic-looking string.  Because the hash is deterministic, the same
  # (value, seed) always produces the same output, satisfying the referential-
  # integrity requirement for :fake.
  # ---------------------------------------------------------------------------

  defp generate_fake(value, seed) do
    <<b0, b1, b2, b3, b4, b5, b6, _rest::binary>> =
      :crypto.hash(:sha256, "#{inspect(seed)}:#{value}")

    first_names = @first_names
    last_names = @last_names
    domains = @domains

    first = Enum.at(first_names, rem(b0, length(first_names)))
    last = Enum.at(last_names, rem(b1, length(last_names)))

    # Use b2 to pick one of four output formats for variety
    case rem(b2, 4) do
      # "Grace Hall"
      0 ->
        "#{first} #{last}"

      # "grace.hall@example.com"
      1 ->
        domain = Enum.at(domains, rem(b3, length(domains)))
        "#{String.downcase(first)}.#{String.downcase(last)}@#{domain}"

      # "Grace1847"  (4-digit numeric suffix)
      2 ->
        suffix = rem(b3 * 256 + b4, 9000) + 1000
        "#{first}#{suffix}"

      # "grace-hall-42"
      3 ->
        suffix = rem(b5 * 256 + b6, 90) + 10
        "#{String.downcase(first)}-#{String.downcase(last)}-#{suffix}"
    end
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule AnonymizerTest do
  use ExUnit.Case, async: false

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
      # TODO
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

  # -------------------------------------------------------
  # Mask length coverage beyond the 1- and 2-character cases
  # -------------------------------------------------------

  describe ":mask length coverage" do
    # Only strings of exactly 1 or 2 characters get special treatment; from
    # 3 characters upward every character between the first and the last is
    # replaced by an asterisk.
    test "strings longer than two characters keep only their outer characters" do
      records = [%{name: "Ann"}, %{name: "Jose"}]
      [three, four] = Anonymizer.anonymize(records, %{name: :mask})

      assert three.name == "A*n"
      assert four.name == "J**e"
    end
  end

  # -------------------------------------------------------
  # Fake generation across a wide range of inputs
  # -------------------------------------------------------

  describe "{:fake, seed} over many distinct values" do
    # Every value handed to the fake rule must come back as a fabricated
    # string, whatever the value happens to be — no input may fail to
    # produce one.
    test "every input value yields a non-empty fake string" do
      records = for i <- 1..200, do: %{name: "user-#{i}"}
      results = Anonymizer.anonymize(records, %{name: {:fake, "wide-range"}})

      assert length(results) == length(records)

      Enum.each(results, fn %{name: fake} ->
        assert is_binary(fake)
        assert String.trim(fake) != ""
      end)
    end
  end
end
```
