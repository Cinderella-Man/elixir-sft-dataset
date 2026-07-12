# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Anonymizer do
  @moduledoc """
  Reversible pseudonymization (tokenization) of record fields with a vault.

  `tokenize/2` replaces each unique original value of a listed field with a
  stable opaque token (`"TOK_<FIELD>_<n>"`, `n` assigned in first-seen order)
  and returns `{tokenized_records, vault}`. `detokenize/2` uses the vault to
  restore originals, leaving any non-token value untouched. The round trip is
  lossless. Only OTP/stdlib modules are used.
  """

  @type vault :: %{forward: map(), reverse: map(), counters: map()}

  @doc """
  Pseudonymizes `fields` across `records`.

  Each unique original value of a listed field is replaced by a stable opaque
  token of the form `"TOK_<FIELD>_<n>"`, where `<FIELD>` is the uppercased
  field name and `<n>` is a per-field, first-seen counter. Distinct fields use
  distinct namespaces even for equal values. Fields not listed, and listed
  fields absent from a record, are left untouched.

  Returns `{tokenized_records, vault}`, where `vault` is an opaque term that
  records the mapping needed to reverse the transformation.
  """
  @spec tokenize([map()], [atom()]) :: {[map()], vault()}
  def tokenize(records, fields) when is_list(records) and is_list(fields) do
    {reversed, vault} =
      Enum.reduce(records, {[], new_vault()}, fn record, {acc, vault} ->
        {record2, vault2} =
          Enum.reduce(fields, {record, vault}, fn field, {rec, v} ->
            case Map.fetch(rec, field) do
              {:ok, value} ->
                {token, v2} = get_or_create_token(v, field, value)
                {Map.put(rec, field, token), v2}

              :error ->
                {rec, v}
            end
          end)

        {[record2 | acc], vault2}
      end)

    {Enum.reverse(reversed), vault}
  end

  @doc """
  Restores original values in `records` using `vault`.

  Every value that is a known token (per the vault) is replaced by its original
  value; values that are not known tokens are left exactly as-is. This is the
  inverse of `tokenize/2`.
  """
  @spec detokenize([map()], vault()) :: [map()]
  def detokenize(records, vault) when is_list(records) and is_map(vault) do
    reverse = Map.get(vault, :reverse, %{})

    Enum.map(records, fn record ->
      Map.new(record, fn {k, v} -> {k, Map.get(reverse, v, v)} end)
    end)
  end

  # --- Internal ---------------------------------------------------------------

  defp new_vault, do: %{forward: %{}, reverse: %{}, counters: %{}}

  defp get_or_create_token(vault, field, value) do
    key = {field, value}

    case Map.fetch(vault.forward, key) do
      {:ok, token} ->
        {token, vault}

      :error ->
        n = Map.get(vault.counters, field, 0) + 1
        token = "TOK_" <> String.upcase(Atom.to_string(field)) <> "_" <> Integer.to_string(n)

        vault = %{
          forward: Map.put(vault.forward, key, token),
          reverse: Map.put(vault.reverse, token, value),
          counters: Map.put(vault.counters, field, n)
        }

        {token, vault}
    end
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
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
      # TODO
    end

    test "listed fields absent from a record are skipped" do
      records = [%{name: "Al"}]
      {[r], _v} = Anonymizer.tokenize(records, [:email])
      refute Map.has_key?(r, :email)
      assert r.name == "Al"
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
end
```
