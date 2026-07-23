# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule AnonymizerTest do
  use ExUnit.Case, async: false

  defp sha256(v), do: :crypto.hash(:sha256, to_string(v)) |> Base.encode16(case: :lower)

  describe "nested path targeting" do
    test "hashes a value at a nested path and leaves siblings alone" do
      records = [%{id: 1, user: %{email: "a@x.com", name: "Al"}}]
      [r] = Anonymizer.anonymize(records, %{"user.email" => :hash})
      assert r.user.email == sha256("a@x.com")
      assert r.user.name == "Al"
      assert r.id == 1
    end

    test "redacts and masks at different nested paths" do
      records = [%{profile: %{ssn: "123-45-6789", first: "Jonathan"}}]
      [r] = Anonymizer.anonymize(records, %{"profile.ssn" => :redact, "profile.first" => :mask})
      assert r.profile.ssn == "[REDACTED]"
      assert r.profile.first == "J******n"
    end
  end

  describe "list descent with []" do
    test "applies a rule to a field of each element in a list" do
      records = [%{orders: [%{card: "1111"}, %{card: "2222"}]}]
      [r] = Anonymizer.anonymize(records, %{"orders[].card" => :redact})
      assert Enum.map(r.orders, & &1.card) == ["[REDACTED]", "[REDACTED]"]
    end

    test "hashes each scalar in a list of scalars (referential integrity within list)" do
      records = [%{tags: ["x", "y", "x"]}]
      [r] = Anonymizer.anonymize(records, %{"tags[]" => :hash})
      assert r.tags == [sha256("x"), sha256("y"), sha256("x")]
    end
  end

  describe "referential integrity" do
    test "same value at different paths and records yields identical output" do
      records = [
        %{user: %{email: "shared@x.com"}, backup: %{email: "shared@x.com"}},
        %{user: %{email: "shared@x.com"}, backup: %{email: "other@x.com"}}
      ]

      [r1, r2] = Anonymizer.anonymize(records, %{"user.email" => :hash, "backup.email" => :hash})
      assert r1.user.email == r1.backup.email
      assert r1.user.email == r2.user.email
      refute r2.user.email == r2.backup.email
    end

    test "deterministic fake preserves referential integrity across nesting" do
      # TODO
    end
  end

  describe "edge cases" do
    test "missing path is ignored gracefully" do
      records = [%{user: %{name: "Alan"}}]
      [r] = Anonymizer.anonymize(records, %{"user.email" => :redact, "user.name" => :mask})
      assert r.user.name == "A**n"
      refute Map.has_key?(r.user, :email)
    end

    test "type mismatch along a path is skipped" do
      records = [%{user: "not-a-map"}]
      [r] = Anonymizer.anonymize(records, %{"user.email" => :redact})
      assert r.user == "not-a-map"
    end

    test "supports string-keyed maps" do
      records = [%{"user" => %{"email" => "a@x.com"}}]
      [r] = Anonymizer.anonymize(records, %{"user.email" => :hash})
      assert r["user"]["email"] == sha256("a@x.com")
    end

    test "empty record list returns empty list" do
      assert [] == Anonymizer.anonymize([], %{"a.b" => :hash})
    end
  end

  test "mask fully masks a 1-character string as *" do
    records = [%{user: %{initial: "Q"}}]
    [r] = Anonymizer.anonymize(records, %{"user.initial" => :mask})
    assert r.user.initial == "*"
  end

  test "mask shows a 2-character string with no masking" do
    records = [%{user: %{code: "ab"}}]
    [r] = Anonymizer.anonymize(records, %{"user.code" => :mask})
    assert r.user.code == "ab"
  end

  test "mask keeps first and last characters of a 3-character string" do
    records = [%{user: %{tag: "abc"}}]
    [r] = Anonymizer.anonymize(records, %{"user.tag" => :mask})
    assert r.user.tag == "a*c"
  end

  test "fake yields a deterministic fabricated string for every value" do
    values = ["Dave", "Carol", "Alice", "Bob"]
    records = [%{names: values}]

    [r1] = Anonymizer.anonymize(records, %{"names[]" => {:fake, "s"}})
    [r2] = Anonymizer.anonymize(records, %{"names[]" => {:fake, "s"}})

    assert r1.names == r2.names
    assert length(r1.names) == length(values)

    for {original, fake} <- Enum.zip(values, r1.names) do
      assert is_binary(fake)
      assert fake != ""
      assert fake != original
    end
  end
end
```
