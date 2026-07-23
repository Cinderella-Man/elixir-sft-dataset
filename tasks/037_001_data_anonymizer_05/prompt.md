# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `anonymize`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

# `Anonymizer` — field anonymization for record lists

Implement an Elixir module `Anonymizer` that anonymizes specified fields in a list of maps (records) according to configurable rules. Single file, complete module.

**Public API**
- `Anonymizer.anonymize(records, rules)` — `records` is a list of maps; `rules` is a map whose keys are field names (atoms) and whose values are one of the rule atoms or tuples below.

**Rules**
- `:hash` — replace the value with its SHA-256 hex digest, encoded as a lowercase hexadecimal string.
- `:mask` — keep the first and last character of the string, replace every middle character with `*`. A 2-character string shows both characters with no masking. A 1-character string is fully masked as `*`.
- `:redact` — replace the value with the string `"[REDACTED]"`.
- `{:fake, seed}` — generate a deterministic fake value (a realistic-looking but fabricated string) derived solely from the original value and the given `seed`. The same input value + seed must always produce the same fake output across calls.

**Return shape**
- Return a list of maps of the same length and structure, with the specified fields transformed in place.
- Fields not mentioned in `rules` must be left untouched.
- If a record does not contain a field named in `rules`, skip that field gracefully for that record — do not add the missing key.

**Referential integrity**
- Preserve across the entire list: if two records share the same original value for a field, their anonymized outputs for that field must also be identical.
- This must hold for all four rule types.

**Constraints**
- Use only the Elixir/OTP standard library — no external dependencies.
- Deliver the complete module in a single file.

## The module with `anonymize` missing

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

  def anonymize(records, rules) when is_list(records) and is_map(rules) do
    # TODO
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

Output only `anonymize` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
