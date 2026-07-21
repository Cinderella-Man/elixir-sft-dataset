# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule MultiSchemaIngestion do
  @moduledoc """
  Reads a JSON array file where each record carries a type discriminator,
  routes records to different Ecto schemas based on a caller-supplied routing
  map, and batch-inserts each group into its respective database table.

  This is useful when a single data feed contains heterogeneous record types
  that belong in different tables (e.g. orders, refunds, adjustments).

  ## Example

      routing = %{
        "order"  => MyApp.Order,
        "refund" => MyApp.Refund
      }

      MultiSchemaIngestion.ingest(MyApp.Repo, routing, "/data/feed.json",
        batch_size:      1_000,
        on_conflict:     :nothing,
        conflict_target: %{MyApp.Order => [:order_id], MyApp.Refund => [:refund_id]},
        type_field:      "record_type"
      )
      #=> {:ok, %{
      #=>   total: 10_000,
      #=>   by_schema: %{
      #=>     MyApp.Order  => %{inserted: 7_500, failed: 0},
      #=>     MyApp.Refund => %{inserted: 2_400, failed: 0}
      #=>   },
      #=>   unroutable: 80,
      #=>   missing_type: 20
      #=> }}
  """

  require Logger

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  @type repo :: module()
  @type schema :: module()
  @type routing :: %{String.t() => schema()}
  @type per_schema_stats :: %{inserted: integer(), failed: integer()}
  @type stats :: %{
          total: integer(),
          by_schema: %{schema() => per_schema_stats()},
          unroutable: integer(),
          missing_type: integer()
        }

  # ---------------------------------------------------------------------------
  # Defaults
  # ---------------------------------------------------------------------------

  @default_batch_size 500
  @default_on_conflict :nothing
  @default_conflict_target :nothing
  @default_type_field "type"

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Ingests records from a JSON array file, routing each record to the
  appropriate Ecto schema based on its type discriminator field.

  See module doc for accepted options.
  """
  @spec ingest(repo(), routing(), String.t(), keyword()) ::
          {:ok, stats()} | {:error, :file_not_found | :invalid_json | :not_a_list}
  def ingest(repo, routing, file_path, opts \\ []) do
    cfg = %{
      batch_size: Keyword.get(opts, :batch_size, @default_batch_size),
      on_conflict: Keyword.get(opts, :on_conflict, @default_on_conflict),
      conflict_target: Keyword.get(opts, :conflict_target, @default_conflict_target),
      type_field: Keyword.get(opts, :type_field, @default_type_field)
    }

    with {:ok, raw} <- read_file(file_path),
         {:ok, parsed} <- parse_json(raw),
         {:ok, records} <- validate_list(parsed) do
      {:ok, process_records(repo, routing, records, cfg)}
    end
  end

  # ---------------------------------------------------------------------------
  # File I/O and validation
  # ---------------------------------------------------------------------------

  defp read_file(path) do
    case File.read(path) do
      {:ok, contents} ->
        {:ok, contents}

      {:error, reason} ->
        Logger.error("[Ingestion] cannot read #{inspect(path)}: #{inspect(reason)}")
        {:error, :file_not_found}
    end
  end

  defp parse_json(raw) do
    case Jason.decode(raw) do
      {:ok, value} ->
        {:ok, value}

      {:error, reason} ->
        Logger.error("[MultiSchemaIngestion] JSON parse error: #{inspect(reason)}")
        {:error, :invalid_json}
    end
  end

  defp validate_list(value) when is_list(value), do: {:ok, value}

  defp validate_list(value) do
    Logger.error("[MultiSchemaIngestion] Expected a JSON array, got: #{inspect(value, limit: 5)}")
    {:error, :not_a_list}
  end

  # ---------------------------------------------------------------------------
  # Record classification and grouping
  # ---------------------------------------------------------------------------

  @spec process_records(repo(), routing(), [map()], map()) :: stats()
  defp process_records(repo, routing, records, cfg) do
    total = length(records)
    type_field = cfg.type_field

    # Classify each record, preserving original order.
    {groups, unroutable, missing_type} =
      Enum.reduce(records, {%{}, 0, 0}, fn record, {groups, unr, miss} ->
        case Map.fetch(record, type_field) do
          :error ->
            Logger.warning("[Ingestion] record missing '#{type_field}', skipping")
            {groups, unr, miss + 1}

          {:ok, type_value} ->
            case Map.fetch(routing, type_value) do
              :error ->
                Logger.warning("[MultiSchemaIngestion] Unknown type '#{type_value}', skipping")
                {groups, unr + 1, miss}

              {:ok, schema} ->
                # Append to the group, maintaining insertion order.
                updated = Map.update(groups, schema, [record], &(&1 ++ [record]))
                {updated, unr, miss}
            end
        end
      end)

    # Process each schema group.
    by_schema =
      groups
      |> Enum.reduce(%{}, fn {schema, schema_records}, acc ->
        schema_stats = insert_schema_group(repo, schema, schema_records, cfg)
        Map.put(acc, schema, schema_stats)
      end)

    # Include schemas from routing that had zero records.
    by_schema =
      routing
      |> Map.values()
      |> Enum.uniq()
      |> Enum.reduce(by_schema, fn schema, acc ->
        Map.put_new(acc, schema, %{inserted: 0, failed: 0})
      end)

    %{
      total: total,
      by_schema: by_schema,
      unroutable: unroutable,
      missing_type: missing_type
    }
  end

  # ---------------------------------------------------------------------------
  # Per-schema batch insertion
  # ---------------------------------------------------------------------------

  @spec insert_schema_group(repo(), schema(), [map()], map()) :: per_schema_stats()
  defp insert_schema_group(repo, schema, records, cfg) do
    schema_keys = schema_field_set(schema)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    conflict_target = resolve_conflict_target(cfg.conflict_target, schema)

    insert_opts = [
      on_conflict: cfg.on_conflict,
      conflict_target: conflict_target
    ]

    initial = %{inserted: 0, failed: 0}

    records
    |> Enum.map(&prepare_row(&1, schema_keys, cfg.type_field, now))
    |> Enum.chunk_every(cfg.batch_size)
    |> Enum.reduce(initial, fn batch, acc ->
      batch_size = length(batch)

      try do
        {count, _} = repo.insert_all(schema, batch, insert_opts)

        new_acc = %{acc | inserted: acc.inserted + count}

        Logger.info(
          "[MultiSchemaIngestion] #{inspect(schema)} batch done — " <>
            "size: #{batch_size}, inserted: #{count}. " <>
            "Running totals — inserted=#{new_acc.inserted} failed=#{new_acc.failed}"
        )

        new_acc
      rescue
        error ->
          Logger.error(
            "[MultiSchemaIngestion] #{inspect(schema)} batch failed " <>
              "(#{batch_size} records skipped): " <>
              Exception.format(:error, error, __STACKTRACE__)
          )

          %{acc | failed: acc.failed + batch_size}
      catch
        kind, reason ->
          Logger.error(
            "[MultiSchemaIngestion] #{inspect(schema)} batch failed " <>
              "with #{kind} (#{batch_size} records skipped): #{inspect(reason)}"
          )

          %{acc | failed: acc.failed + batch_size}
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Row preparation
  # ---------------------------------------------------------------------------

  @spec schema_field_set(schema()) :: MapSet.t(String.t())
  defp schema_field_set(schema) do
    schema.__schema__(:fields)
    |> Enum.map(&Atom.to_string/1)
    |> MapSet.new()
  end

  @spec prepare_row(map(), MapSet.t(String.t()), String.t(), NaiveDateTime.t()) :: map()
  defp prepare_row(row, schema_keys, type_field, now) do
    base =
      row
      |> Map.delete(type_field)
      |> Enum.filter(fn {k, _v} -> MapSet.member?(schema_keys, k) end)
      |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), v} end)
      |> Map.new()

    base
    |> maybe_put_new(:inserted_at, now, schema_keys)
    |> maybe_put_new(:updated_at, now, schema_keys)
  end

  defp maybe_put_new(row, field, value, schema_keys) do
    if MapSet.member?(schema_keys, Atom.to_string(field)) do
      Map.put_new(row, field, value)
    else
      row
    end
  end

  # ---------------------------------------------------------------------------
  # Conflict target resolution
  # ---------------------------------------------------------------------------

  @spec resolve_conflict_target(atom() | [atom()] | map(), schema()) :: atom() | [atom()]
  defp resolve_conflict_target(target, _schema) when is_atom(target), do: target
  defp resolve_conflict_target(target, _schema) when is_list(target), do: target

  defp resolve_conflict_target(target, schema) when is_map(target) do
    Map.get(target, schema, :nothing)
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule MultiSchemaIngestionTest do
  use ExUnit.Case, async: false

  # ---------------------------------------------------------------------------
  # Minimal in-memory Ecto setup
  # ---------------------------------------------------------------------------

  defmodule TestRepo do
    use Ecto.Repo, otp_app: :multi_schema_ingestion, adapter: Ecto.Adapters.SQLite3
  end

  defmodule Order do
    use Ecto.Schema

    @primary_key {:id, :id, autogenerate: true}

    schema "orders" do
      field(:order_id, :string)
      field(:customer, :string)
      field(:amount, :integer)
      timestamps()
    end
  end

  defmodule Refund do
    use Ecto.Schema

    @primary_key {:id, :id, autogenerate: true}

    schema "refunds" do
      field(:refund_id, :string)
      field(:reason, :string)
      field(:amount, :integer)
      timestamps()
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp write_json!(path, data), do: File.write!(path, Jason.encode!(data))

  defp tmp_path(name),
    do:
      Path.join(
        System.tmp_dir!(),
        "#{System.pid()}_#{System.unique_integer([:positive])}_#{name}"
      )

  defp routing do
    %{
      "order" => Order,
      "refund" => Refund
    }
  end

  defp all_orders, do: TestRepo.all(Order)
  defp all_refunds, do: TestRepo.all(Refund)

  # ---------------------------------------------------------------------------
  # Setup / teardown
  # ---------------------------------------------------------------------------

  setup_all do
    Application.put_env(:multi_schema_ingestion, MultiSchemaIngestionTest.TestRepo,
      database: ":memory:",
      pool_size: 1
    )

    {:ok, _} = MultiSchemaIngestionTest.TestRepo.start_link()

    MultiSchemaIngestionTest.TestRepo.query!(
      """
      CREATE TABLE orders (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id    TEXT    UNIQUE,
        customer    TEXT    NOT NULL,
        amount      INTEGER,
        inserted_at TEXT    NOT NULL,
        updated_at  TEXT    NOT NULL
      )
      """,
      []
    )

    MultiSchemaIngestionTest.TestRepo.query!(
      """
      CREATE TABLE refunds (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        refund_id   TEXT    UNIQUE,
        reason      TEXT    NOT NULL,
        amount      INTEGER,
        inserted_at TEXT    NOT NULL,
        updated_at  TEXT    NOT NULL
      )
      """,
      []
    )

    :ok
  end

  setup do
    TestRepo.delete_all(Order)
    TestRepo.delete_all(Refund)
    :ok
  end

  # ---------------------------------------------------------------------------
  # Happy-path: mixed types routed to correct tables
  # ---------------------------------------------------------------------------

  test "routes records to correct schemas based on type field" do
    records = [
      %{"type" => "order", "order_id" => "o-1", "customer" => "Alice", "amount" => 100},
      %{"type" => "refund", "refund_id" => "r-1", "reason" => "damaged", "amount" => 50},
      %{"type" => "order", "order_id" => "o-2", "customer" => "Bob", "amount" => 200},
      %{"type" => "order", "order_id" => "o-3", "customer" => "Carol", "amount" => 300},
      %{"type" => "refund", "refund_id" => "r-2", "reason" => "wrong item", "amount" => 75}
    ]

    path = tmp_path("mixed_types.json")
    write_json!(path, records)

    assert {:ok, stats} =
             MultiSchemaIngestion.ingest(TestRepo, routing(), path,
               conflict_target: %{Order => [:order_id], Refund => [:refund_id]},
               batch_size: 2
             )

    assert stats.total == 5
    assert stats.unroutable == 0
    assert stats.missing_type == 0

    assert stats.by_schema[Order].inserted == 3
    assert stats.by_schema[Order].failed == 0
    assert stats.by_schema[Refund].inserted == 2
    assert stats.by_schema[Refund].failed == 0

    assert length(all_orders()) == 3
    assert length(all_refunds()) == 2
  end

  # ---------------------------------------------------------------------------
  # Unroutable records: type not in routing map
  # ---------------------------------------------------------------------------

  test "counts records with unknown type as unroutable" do
    records = [
      %{"type" => "order", "order_id" => "o-1", "customer" => "Alice", "amount" => 100},
      %{"type" => "unknown", "foo" => "bar"},
      %{"type" => "refund", "refund_id" => "r-1", "reason" => "oops", "amount" => 25},
      %{"type" => "mystery", "baz" => "qux"}
    ]

    path = tmp_path("unroutable.json")
    write_json!(path, records)

    assert {:ok, stats} =
             MultiSchemaIngestion.ingest(TestRepo, routing(), path,
               conflict_target: %{Order => [:order_id], Refund => [:refund_id]}
             )

    assert stats.total == 4
    assert stats.unroutable == 2
    assert stats.missing_type == 0
    assert stats.by_schema[Order].inserted == 1
    assert stats.by_schema[Refund].inserted == 1
  end

  # ---------------------------------------------------------------------------
  # Missing type field
  # ---------------------------------------------------------------------------

  test "counts records with no type field as missing_type" do
    records = [
      %{"type" => "order", "order_id" => "o-1", "customer" => "Alice", "amount" => 100},
      %{"order_id" => "o-2", "customer" => "Bob", "amount" => 200},
      %{"foo" => "bar"}
    ]

    path = tmp_path("missing_type.json")
    write_json!(path, records)

    assert {:ok, stats} =
             MultiSchemaIngestion.ingest(TestRepo, routing(), path,
               conflict_target: %{Order => [:order_id], Refund => [:refund_id]}
             )

    assert stats.total == 3
    assert stats.missing_type == 2
    assert stats.unroutable == 0
    assert stats.by_schema[Order].inserted == 1
  end

  # ---------------------------------------------------------------------------
  # Custom type_field option
  # ---------------------------------------------------------------------------

  test "supports custom type_field option" do
    records = [
      %{"record_kind" => "order", "order_id" => "o-1", "customer" => "X", "amount" => 10},
      %{"record_kind" => "refund", "refund_id" => "r-1", "reason" => "Y", "amount" => 5}
    ]

    path = tmp_path("custom_type_field.json")
    write_json!(path, records)

    assert {:ok, stats} =
             MultiSchemaIngestion.ingest(TestRepo, routing(), path,
               conflict_target: %{Order => [:order_id], Refund => [:refund_id]},
               type_field: "record_kind"
             )

    assert stats.total == 2
    assert stats.by_schema[Order].inserted == 1
    assert stats.by_schema[Refund].inserted == 1
  end

  # ---------------------------------------------------------------------------
  # Per-schema conflict target via map
  # ---------------------------------------------------------------------------

  test "uses per-schema conflict targets from a map" do
    records = [
      %{"type" => "order", "order_id" => "o-1", "customer" => "Alice", "amount" => 100},
      %{"type" => "refund", "refund_id" => "r-1", "reason" => "damaged", "amount" => 50}
    ]

    path = tmp_path("per_schema_conflict.json")
    write_json!(path, records)

    # First insert
    MultiSchemaIngestion.ingest(TestRepo, routing(), path,
      conflict_target: %{Order => [:order_id], Refund => [:refund_id]},
      on_conflict: :nothing
    )

    # Second insert — same IDs, on_conflict: :nothing means no error, no update
    assert {:ok, stats} =
             MultiSchemaIngestion.ingest(TestRepo, routing(), path,
               conflict_target: %{Order => [:order_id], Refund => [:refund_id]},
               on_conflict: :nothing
             )

    assert stats.by_schema[Order].failed == 0
    assert stats.by_schema[Refund].failed == 0

    # Still only 1 of each
    assert length(all_orders()) == 1
    assert length(all_refunds()) == 1
  end

  # ---------------------------------------------------------------------------
  # Graceful error: file not found
  # ---------------------------------------------------------------------------

  test "returns {:error, :file_not_found} for missing file" do
    assert {:error, :file_not_found} =
             MultiSchemaIngestion.ingest(TestRepo, routing(), "/no/such/file.json")
  end

  # ---------------------------------------------------------------------------
  # Graceful error: malformed JSON
  # ---------------------------------------------------------------------------

  test "returns {:error, :invalid_json} for a malformed JSON file" do
    # TODO
  end

  # ---------------------------------------------------------------------------
  # Graceful error: not a list
  # ---------------------------------------------------------------------------

  test "returns {:error, :not_a_list} when JSON root is not an array" do
    path = tmp_path("object.json")
    write_json!(path, %{"key" => "value"})

    assert {:error, :not_a_list} =
             MultiSchemaIngestion.ingest(TestRepo, routing(), path)
  end

  # ---------------------------------------------------------------------------
  # Empty array
  # ---------------------------------------------------------------------------

  test "handles an empty JSON array gracefully" do
    path = tmp_path("empty_multi.json")
    write_json!(path, [])

    assert {:ok, stats} =
             MultiSchemaIngestion.ingest(TestRepo, routing(), path)

    assert stats.total == 0
    assert stats.unroutable == 0
    assert stats.missing_type == 0
    # Both schemas should appear in by_schema with zero counts
    assert stats.by_schema[Order] == %{inserted: 0, failed: 0}
    assert stats.by_schema[Refund] == %{inserted: 0, failed: 0}
  end

  # ---------------------------------------------------------------------------
  # Partial failure: bad batch in one schema doesn't affect others
  # ---------------------------------------------------------------------------

  test "continues processing other schemas after a batch failure" do
    good_orders =
      Enum.map(1..5, fn i ->
        %{"type" => "order", "order_id" => "o-#{i}", "customer" => "c #{i}", "amount" => i}
      end)

    # Refunds missing the required "reason" field — NOT NULL will fail
    bad_refunds =
      Enum.map(1..3, fn i ->
        %{"type" => "refund", "refund_id" => "bad-#{i}", "amount" => i}
      end)

    good_refunds =
      Enum.map(1..2, fn i ->
        %{"type" => "refund", "refund_id" => "good-#{i}", "reason" => "ok #{i}", "amount" => i}
      end)

    records = good_orders ++ bad_refunds ++ good_refunds
    path = tmp_path("partial_multi.json")
    write_json!(path, records)

    assert {:ok, stats} =
             MultiSchemaIngestion.ingest(TestRepo, routing(), path,
               conflict_target: %{Order => [:order_id], Refund => [:refund_id]},
               batch_size: 3
             )

    assert stats.total == 10

    # Orders should all succeed
    assert stats.by_schema[Order].inserted == 5
    assert stats.by_schema[Order].failed == 0

    # Refunds: batch of bad_refunds (3) should fail, batch of good_refunds (2) should succeed
    assert stats.by_schema[Refund].failed == 3
    assert stats.by_schema[Refund].inserted == 2

    assert length(all_orders()) == 5
    assert length(all_refunds()) == 2
  end

  # ---------------------------------------------------------------------------
  # Within-group ordering: each schema group lands in original file order
  # ---------------------------------------------------------------------------

  test "inserts each schema group in the order records appeared in the file" do
    import Ecto.Query, only: [from: 2]

    # Types are interleaved so a group that preserves file order is
    # distinguishable from one that reverses or shuffles it, and batch_size
    # forces each group to span multiple insert_all calls.
    records = [
      %{"type" => "order", "order_id" => "o-a", "customer" => "A", "amount" => 1},
      %{"type" => "refund", "refund_id" => "r-a", "reason" => "ra", "amount" => 10},
      %{"type" => "order", "order_id" => "o-b", "customer" => "B", "amount" => 2},
      %{"type" => "order", "order_id" => "o-c", "customer" => "C", "amount" => 3},
      %{"type" => "refund", "refund_id" => "r-b", "reason" => "rb", "amount" => 20},
      %{"type" => "order", "order_id" => "o-d", "customer" => "D", "amount" => 4},
      %{"type" => "refund", "refund_id" => "r-c", "reason" => "rc", "amount" => 30}
    ]

    path = tmp_path("group_order.json")
    write_json!(path, records)

    assert {:ok, stats} =
             MultiSchemaIngestion.ingest(TestRepo, routing(), path,
               conflict_target: %{Order => [:order_id], Refund => [:refund_id]},
               batch_size: 2
             )

    assert stats.by_schema[Order].inserted == 4
    assert stats.by_schema[Refund].inserted == 3

    # Autoincrement ids increase with insertion order, so ordering rows by id
    # replays the sequence in which each group was written.
    order_ids = TestRepo.all(from(o in Order, order_by: [asc: o.id], select: o.order_id))
    refund_ids = TestRepo.all(from(r in Refund, order_by: [asc: r.id], select: r.refund_id))

    assert order_ids == ["o-a", "o-b", "o-c", "o-d"]
    assert refund_ids == ["r-a", "r-b", "r-c"]
  end
end
```
