# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `safe_existing_atom`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

Write me an Elixir module called `Anonymizer` that anonymizes fields inside **deeply nested** record maps, addressing those fields by string **paths** rather than flat top-level keys.

I need this function in the public API:
- `Anonymizer.anonymize(records, rules)` where `records` is a list of (possibly deeply nested) maps and `rules` is a map whose keys are **string paths** and whose values are one of the following rule atoms or tuples:
  - `:hash` — replace the value with its SHA-256 digest encoded as a **lower-case** hexadecimal string
  - `:mask` — keep the first and last character of the string, replace every middle character with `*`. A string of 2 characters shows both with no masking. A string of 1 character is fully masked as `*`.
  - `:redact` — replace the value with the string `"[REDACTED]"`
  - `{:fake, seed}` — generate a deterministic fake value (a realistic-looking but fabricated string) derived solely from the original value and the given `seed`. The same input value + seed must always produce the same fake output across calls.

Path syntax:
- Dot notation descends into nested maps: `"user.email"` targets `record[:user][:email]`.
- A segment ending in `[]` descends into **every element** of a list: `"orders[].card"` applies the rule to the `:card` field of every element of the `:orders` list, and `"tags[]"` applies the rule to every scalar element of the `:tags` list.
- Map keys may be atoms or strings; a path segment must match whichever the record uses.

The function must return a list of maps of the same length and structure, with the addressed values transformed in place. Anything not addressed by a path must be left untouched. A path that does not resolve in a given record (missing key, or a type mismatch such as trying to descend into a non-map) must be skipped gracefully rather than raising.

Referential integrity must be preserved across the entire list: if two locations (in the same or different records) hold the same original value for paths that share a rule, their anonymized outputs must be identical. This must hold for all four rule types.

Use only the Elixir/OTP standard library — no external dependencies. Give me the complete module in a single file.

## The module with `safe_existing_atom` missing

```elixir
defmodule Anonymizer do
  @moduledoc """
  Path-addressed anonymizer for deeply nested record maps.

  Rules are keyed by string paths:

    * `"user.email"`     – descend into nested maps via dot notation.
    * `"orders[].card"`  – a `[]` segment descends into every element of a list.
    * `"tags[]"`         – apply the rule to every scalar element of a list.

  Rule values are `:hash`, `:mask`, `:redact`, or `{:fake, seed}` (see the
  base task). Every rule is a pure function of its inputs, so two locations
  holding the same original value are anonymized identically (referential
  integrity). Only OTP/stdlib modules are used.
  """

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

  @doc """
  Anonymizes `records` (a list of possibly deeply nested maps) according to
  `rules`, a map of string paths to rule atoms/tuples.

  Returns a list of the same length and structure, with addressed values
  transformed in place. Paths that do not resolve in a given record are
  skipped gracefully.
  """
  @spec anonymize([map()], %{optional(String.t()) => term()}) :: [map()]
  def anonymize(records, rules) when is_list(records) and is_map(rules) do
    compiled = Enum.map(rules, fn {path, rule} -> {parse_path(path), rule} end)

    Enum.map(records, fn record ->
      Enum.reduce(compiled, record, fn {segments, rule}, acc ->
        update_path(acc, segments, rule)
      end)
    end)
  end

  # --- Path parsing -----------------------------------------------------------

  defp parse_path(path) do
    path
    |> String.split(".")
    |> Enum.flat_map(&parse_segment/1)
  end

  defp parse_segment(seg) do
    if String.ends_with?(seg, "[]") do
      [{:key, String.trim_trailing(seg, "[]")}, :each]
    else
      [{:key, seg}]
    end
  end

  # --- Path traversal ---------------------------------------------------------

  defp update_path(value, [], rule), do: apply_rule(value, rule)

  defp update_path(map, [{:key, key} | rest], rule) when is_map(map) do
    case fetch_key(map, key) do
      {:ok, actual_key, value} ->
        Map.put(map, actual_key, update_path(value, rest, rule))

      :error ->
        map
    end
  end

  defp update_path(list, [:each | rest], rule) when is_list(list) do
    Enum.map(list, &update_path(&1, rest, rule))
  end

  defp update_path(other, _segments, _rule), do: other

  defp fetch_key(map, key) do
    atom_key = safe_existing_atom(key)

    cond do
      Map.has_key?(map, key) ->
        {:ok, key, Map.fetch!(map, key)}

      atom_key != nil and Map.has_key?(map, atom_key) ->
        {:ok, atom_key, Map.fetch!(map, atom_key)}

      true ->
        :error
    end
  end

  defp safe_existing_atom(str) do
    # TODO
  end

  # --- Rule dispatch ----------------------------------------------------------

  defp apply_rule(_value, :redact), do: "[REDACTED]"

  defp apply_rule(value, :hash) do
    :crypto.hash(:sha256, to_string(value)) |> Base.encode16(case: :lower)
  end

  defp apply_rule(value, :mask) do
    str = to_string(value)

    case String.length(str) do
      0 -> str
      1 -> "*"
      2 -> str
      len -> String.at(str, 0) <> String.duplicate("*", len - 2) <> String.at(str, len - 1)
    end
  end

  defp apply_rule(value, {:fake, seed}), do: generate_fake(to_string(value), seed)

  # --- Deterministic fake generator -------------------------------------------

  defp generate_fake(value, seed) do
    <<b0, b1, b2, b3, b4, b5, b6, _rest::binary>> =
      :crypto.hash(:sha256, "#{inspect(seed)}:#{value}")

    first = Enum.at(@first_names, rem(b0, length(@first_names)))
    last = Enum.at(@last_names, rem(b1, length(@last_names)))

    case rem(b2, 4) do
      0 ->
        "#{first} #{last}"

      1 ->
        domain = Enum.at(@domains, rem(b3, length(@domains)))
        "#{String.downcase(first)}.#{String.downcase(last)}@#{domain}"

      2 ->
        suffix = rem(b3 * 256 + b4, 9000) + 1000
        "#{first}#{suffix}"

      3 ->
        suffix = rem(b5 * 256 + b6, 90) + 10
        "#{String.downcase(first)}-#{String.downcase(last)}-#{suffix}"
    end
  end
end
```

Output only `safe_existing_atom` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
