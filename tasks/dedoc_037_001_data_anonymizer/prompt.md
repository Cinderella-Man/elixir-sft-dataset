# Restore the documentation

The module below works and is fully tested — its behavior is final. What it
lost is every piece of documentation. Put it back:

- a `@moduledoc` covering purpose and usage,
- a `@doc` on each public function,
- a `@spec` on each public function (plus `@type`s where they clarify).

And keep your hands off the code itself: no renames, no refactors, no added
or removed functions, identical behavior everywhere. Return the whole
documented module in one file.

## The module

```elixir
defmodule Anonymizer do
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
