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
    path = tmp_path("bad.json")
    File.write!(path, "{not json at all}")

    assert {:error, :invalid_json} =
             MultiSchemaIngestion.ingest(TestRepo, routing(), path)
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

  test "schema groups are processed in first-appearance order, not term order" do
    # Refund appears FIRST in the file while the Order atom sorts first, so a
    # map-iteration implementation is distinguishable from the required one.
    records = [
      %{"type" => "refund", "refund_id" => "r-1", "reason" => "r", "amount" => 1},
      %{"type" => "order", "order_id" => "o-1", "customer" => "A", "amount" => 1}
    ]

    path = tmp_path("group_first_appearance.json")
    write_json!(path, records)

    log =
      ExUnit.CaptureLog.capture_log([level: :info], fn ->
        assert {:ok, _} =
                 MultiSchemaIngestion.ingest(TestRepo, routing(), path,
                   conflict_target: %{Order => [:order_id], Refund => [:refund_id]},
                   batch_size: 10
                 )
      end)

    # The contract's own per-batch info lines carry the schema name: the
    # first-appearing group's line must come first.
    refund_at = :binary.match(log, "Refund") |> elem(0)
    order_at = :binary.match(log, "Order") |> elem(0)
    assert refund_at < order_at
  end

  test "a non-string type discriminator value is counted unroutable, never raises" do
    records = [
      %{"type" => %{"weird" => 1}, "order_id" => "o-x"},
      %{"type" => [1, 2], "order_id" => "o-y"},
      %{"type" => "order", "order_id" => "o-1", "customer" => "A", "amount" => 1}
    ]

    path = tmp_path("nonstring_type.json")
    write_json!(path, records)

    assert {:ok, stats} =
             MultiSchemaIngestion.ingest(TestRepo, routing(), path,
               conflict_target: %{Order => [:order_id], Refund => [:refund_id]}
             )

    assert stats.total == 3
    assert stats.unroutable == 2
    assert stats.by_schema[Order].inserted == 1
  end

  test "a non-object array element is counted missing_type, never raises" do
    path = tmp_path("nonobject_records.json")

    File.write!(
      path,
      Jason.encode!([
        "just a string",
        42,
        %{"type" => "order", "order_id" => "o-1", "customer" => "A", "amount" => 1}
      ])
    )

    assert {:ok, stats} =
             MultiSchemaIngestion.ingest(TestRepo, routing(), path,
               conflict_target: %{Order => [:order_id], Refund => [:refund_id]}
             )

    assert stats.total == 3
    assert stats.missing_type == 2
    assert stats.by_schema[Order].inserted == 1
  end

  test "a failed batch still gets its Logger.info running-totals line" do
    # Refunds missing the NOT NULL "reason" fail their batch; the good batch
    # after it succeeds. "After every batch" is unconditional, so TWO refund
    # info lines must appear — the error log does not replace the first.
    records =
      Enum.map(1..3, fn i ->
        %{"type" => "refund", "refund_id" => "bad-#{i}", "amount" => i}
      end) ++
        Enum.map(1..2, fn i ->
          %{"type" => "refund", "refund_id" => "good-#{i}", "reason" => "ok", "amount" => i}
        end)

    path = tmp_path("failed_batch_info.json")
    write_json!(path, records)

    log =
      ExUnit.CaptureLog.capture_log([level: :info], fn ->
        assert {:ok, stats} =
                 MultiSchemaIngestion.ingest(TestRepo, routing(), path,
                   conflict_target: %{Order => [:order_id], Refund => [:refund_id]},
                   batch_size: 3
                 )

        assert stats.by_schema[Refund].failed == 3
        assert stats.by_schema[Refund].inserted == 2
      end)

    info_lines =
      log
      |> String.split("\n")
      |> Enum.filter(&(&1 =~ "[info]" and &1 =~ "Refund"))

    assert length(info_lines) == 2
  end
end
