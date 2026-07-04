Implement the private `generate_fake/2` function. It takes a stringified original
`value` and a `seed` and returns a deterministic, realistic-looking but fabricated
string derived solely from those two inputs — the same `value` + `seed` must always
produce the same output. Compute a SHA-256 digest of `"#{inspect(seed)}:#{value}"`
and bind its first seven bytes (call them `b0` through `b6`). Use these bytes as
deterministic indices/values via `rem/2`:

- Pick a `first` name from `@first_names` using `b0` and a `last` name from
  `@last_names` using `b1` (index with `rem(byte, length(list))`).
- Branch on `rem(b2, 4)` to choose one of four output shapes:
  - `0` → `"#{first} #{last}"`
  - `1` → an email `"#{downcased first}.#{downcased last}@#{domain}"`, where
    `domain` comes from `@domains` indexed by `b3`.
  - `2` → `"#{first}#{suffix}"`, where `suffix` is `rem(b3 * 256 + b4, 9000) + 1000`.
  - `3` → `"#{downcased first}-#{downcased last}-#{suffix}"`, where `suffix` is
    `rem(b5 * 256 + b6, 90) + 10`.

Use only the Elixir/OTP standard library.

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
    String.to_existing_atom(str)
  rescue
    ArgumentError -> nil
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
    # TODO
  end
end
```