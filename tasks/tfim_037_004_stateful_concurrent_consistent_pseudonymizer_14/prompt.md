# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Anonymizer do
  @moduledoc """
  Stateful, concurrent anonymizer.

  A GenServer holds the accumulated `original -> pseudonym` tables so that
  referential integrity is preserved across every batch. `anonymize/2`
  processes records concurrently with `Task.async_stream` while all pseudonym
  assignment is serialized through the server, keeping it race-free. Supported
  rules: `{:pseudonym, prefix}`, `:hash`, `:redact`. Only OTP/stdlib is used.
  """

  use GenServer

  # --- Public API -------------------------------------------------------------

  @doc """
  Start the anonymizer server.

  `rules` is a map of field-name atoms to one of `{:pseudonym, prefix}`,
  `:hash`, or `:redact`. Returns `{:ok, pid}`.
  """
  @spec start_link(map()) :: GenServer.on_start()
  def start_link(rules) when is_map(rules) do
    GenServer.start_link(__MODULE__, rules)
  end

  @doc """
  Transform a list of maps, returning the transformed list in the same order.

  Records are processed concurrently while pseudonym assignment stays
  race-free and referentially consistent within and across calls. Fields not
  named in the rules, and rule fields missing from a record, are left as-is.
  """
  @spec anonymize(pid(), [map()]) :: [map()]
  def anonymize(pid, records) when is_list(records) do
    rules = GenServer.call(pid, :get_rules)

    records
    |> Task.async_stream(
      fn record ->
        Enum.reduce(rules, record, fn {field, rule}, acc ->
          case Map.fetch(acc, field) do
            {:ok, value} -> Map.put(acc, field, resolve(pid, field, value, rule))
            :error -> acc
          end
        end)
      end,
      max_concurrency: max(System.schedulers_online(), 2),
      ordered: true,
      timeout: :infinity
    )
    |> Enum.map(fn {:ok, record} -> record end)
  end

  @doc """
  Return the current `%{original_value => pseudonym}` table for `field`.
  """
  @spec mapping(pid(), atom()) :: map()
  def mapping(pid, field) do
    GenServer.call(pid, {:mapping, field})
  end

  # --- Rule resolution --------------------------------------------------------

  defp resolve(_pid, _field, _value, :redact), do: "[REDACTED]"

  defp resolve(_pid, _field, value, :hash) do
    :crypto.hash(:sha256, to_string(value)) |> Base.encode16(case: :lower)
  end

  defp resolve(pid, field, value, {:pseudonym, prefix}) do
    GenServer.call(pid, {:pseudonym, field, value, prefix})
  end

  # --- GenServer callbacks ----------------------------------------------------

  @impl true
  def init(rules) do
    {:ok, %{rules: rules, maps: %{}, counters: %{}}}
  end

  @impl true
  def handle_call(:get_rules, _from, state) do
    {:reply, state.rules, state}
  end

  def handle_call({:mapping, field}, _from, state) do
    {:reply, Map.get(state.maps, field, %{}), state}
  end

  def handle_call({:pseudonym, field, value, prefix}, _from, state) do
    field_map = Map.get(state.maps, field, %{})

    case Map.fetch(field_map, value) do
      {:ok, pseudonym} ->
        {:reply, pseudonym, state}

      :error ->
        n = Map.get(state.counters, field, 0) + 1
        pseudonym = "#{prefix}_#{n}"

        state = %{
          state
          | maps: Map.put(state.maps, field, Map.put(field_map, value, pseudonym)),
            counters: Map.put(state.counters, field, n)
        }

        {:reply, pseudonym, state}
    end
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule AnonymizerTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} =
      Anonymizer.start_link(%{name: {:pseudonym, "PERSON"}, email: :hash, ssn: :redact})

    {:ok, pid: pid}
  end

  test "pseudonyms follow prefix_N format and preserve referential integrity", %{pid: pid} do
    records = [%{name: "Alice"}, %{name: "Bob"}, %{name: "Alice"}]
    [r1, r2, r3] = Anonymizer.anonymize(pid, records)
    assert r1.name == r3.name
    refute r1.name == r2.name
    assert r1.name =~ ~r/^PERSON_\d+$/
    assert r2.name =~ ~r/^PERSON_\d+$/
  end

  test "preserves record order under concurrent processing", %{pid: pid} do
    records = for i <- 1..50, do: %{name: "user#{i}", id: i}
    result = Anonymizer.anonymize(pid, records)
    assert Enum.map(result, & &1.id) == Enum.to_list(1..50)
  end

  test "referential integrity holds across separate batches", %{pid: pid} do
    [a] = Anonymizer.anonymize(pid, [%{name: "Alice"}])
    [b] = Anonymizer.anonymize(pid, [%{name: "Alice"}])
    assert a.name == b.name
  end

  test "hash and redact rules work alongside pseudonyms", %{pid: pid} do
    [r] = Anonymizer.anonymize(pid, [%{name: "Alice", email: "a@x.com", ssn: "111"}])
    assert r.name =~ ~r/^PERSON_\d+$/
    assert r.email == :crypto.hash(:sha256, "a@x.com") |> Base.encode16(case: :lower)
    assert r.ssn == "[REDACTED]"
  end

  test "hash is consistent for the same value", %{pid: pid} do
    [r1, r2] = Anonymizer.anonymize(pid, [%{email: "a@x.com"}, %{email: "a@x.com"}])
    assert r1.email == r2.email
  end

  test "distinct values get distinct pseudonyms under concurrent load", %{pid: pid} do
    records = for i <- 1..200, do: %{name: "name_#{i}"}
    result = Anonymizer.anonymize(pid, records)
    pseudonyms = Enum.map(result, & &1.name)
    assert length(Enum.uniq(pseudonyms)) == 200
  end

  test "mapping/2 exposes the value -> pseudonym table", %{pid: pid} do
    Anonymizer.anonymize(pid, [%{name: "Alice"}, %{name: "Bob"}])
    mapping = Anonymizer.mapping(pid, :name)
    assert map_size(mapping) == 2
    assert Map.has_key?(mapping, "Alice")
  end

  test "unlisted fields and missing rule fields are handled gracefully", %{pid: pid} do
    [r] = Anonymizer.anonymize(pid, [%{name: "Alice", role: "admin"}])
    assert r.role == "admin"
    assert r.name =~ ~r/^PERSON_\d+$/

    [r2] = Anonymizer.anonymize(pid, [%{email: "a@x.com"}])
    assert Map.has_key?(r2, :email)
  end

  test "distinct non-string and string values are not conflated into one pseudonym", %{pid: pid} do
    [r1, r2, r3] = Anonymizer.anonymize(pid, [%{name: 42}, %{name: "42"}, %{name: 42}])
    assert r1.name == r3.name
    refute r1.name == r2.name
    assert map_size(Anonymizer.mapping(pid, :name)) == 2
  end

  test "mapping/2 keys are the original values, not stringified copies", %{pid: pid} do
    Anonymizer.anonymize(pid, [%{name: 42}])
    mapping = Anonymizer.mapping(pid, :name)
    assert Map.has_key?(mapping, 42)
    assert mapping[42] =~ ~r/^PERSON_\d+$/
  end

  test "each pseudonymized field numbers independently with its own prefix" do
    {:ok, pid} = Anonymizer.start_link(%{name: {:pseudonym, "PERSON"}, org: {:pseudonym, "ORG"}})
    [r] = Anonymizer.anonymize(pid, [%{name: "Acme", org: "Acme"}])
    assert r.name == "PERSON_1"
    assert r.org == "ORG_1"
    assert Anonymizer.mapping(pid, :name) == %{"Acme" => "PERSON_1"}
    assert Anonymizer.mapping(pid, :org) == %{"Acme" => "ORG_1"}
  end

  test "records missing rule fields do not gain those keys", %{pid: pid} do
    [r] = Anonymizer.anonymize(pid, [%{role: "admin"}])
    assert r == %{role: "admin"}
    refute Map.has_key?(r, :name)
    refute Map.has_key?(r, :email)
    refute Map.has_key?(r, :ssn)
  end

  test "mapping/2 accumulates entries across separate anonymize calls", %{pid: pid} do
    Anonymizer.anonymize(pid, [%{name: "Alice"}])
    Anonymizer.anonymize(pid, [%{name: "Bob"}, %{name: "Alice"}])
    mapping = Anonymizer.mapping(pid, :name)
    assert map_size(mapping) == 2
    assert Map.has_key?(mapping, "Alice")
    assert Map.has_key?(mapping, "Bob")
    assert length(Enum.uniq(Map.values(mapping))) == 2
  end

  test "start_link/1 returns {:ok, pid} for a rules map" do
    # TODO
  end
end
```
