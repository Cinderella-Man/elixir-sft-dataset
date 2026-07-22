defmodule CsvIngestionTest do
  use ExUnit.Case, async: false

  # ---------------------------------------------------------------------------
  # Minimal in-memory Ecto setup
  # ---------------------------------------------------------------------------

  defmodule TestRepo do
    use Ecto.Repo, otp_app: :csv_ingestion, adapter: Ecto.Adapters.SQLite3
  end

  defmodule Product do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :id, autogenerate: true}

    schema "products" do
      field(:external_id, :string)
      field(:name, :string)
      field(:price, :integer)
      timestamps()
    end

    def changeset(product, attrs) do
      product
      |> cast(attrs, [:external_id, :name, :price])
      |> validate_required([:external_id, :name])
      |> unique_constraint(:external_id)
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp write_csv!(path, header, rows) do
    lines =
      [Enum.join(header, ",") | Enum.map(rows, &Enum.join(&1, ","))]
      |> Enum.join("\n")

    File.write!(path, lines)
  end

  defp tmp_path(name),
    do:
      Path.join(
        System.tmp_dir!(),
        "#{System.pid()}_#{System.unique_integer([:positive])}_#{name}"
      )

  defp all_products, do: TestRepo.all(Product)

  # ---------------------------------------------------------------------------
  # Setup / teardown
  # ---------------------------------------------------------------------------

  setup_all do
    Application.put_env(:csv_ingestion, CsvIngestionTest.TestRepo,
      database: ":memory:",
      pool_size: 1
    )

    {:ok, _} = CsvIngestionTest.TestRepo.start_link()

    CsvIngestionTest.TestRepo.query!(
      """
      CREATE TABLE products (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        external_id TEXT    UNIQUE,
        name        TEXT    NOT NULL,
        price       INTEGER,
        inserted_at TEXT    NOT NULL,
        updated_at  TEXT    NOT NULL
      )
      """,
      []
    )

    :ok
  end

  setup do
    TestRepo.delete_all(Product)
    :ok
  end

  # ---------------------------------------------------------------------------
  # Happy-path: fresh inserts
  # ---------------------------------------------------------------------------

  test "inserts all valid rows from a CSV file" do
    header = ["external_id", "name", "price"]
    rows = Enum.map(1..10, fn i -> ["eid-#{i}", "product #{i}", "#{i * 100}"] end)

    path = tmp_path("fresh_insert.csv")
    write_csv!(path, header, rows)

    assert {:ok, stats} =
             CsvIngestion.ingest(TestRepo, Product, path,
               conflict_target: [:external_id],
               batch_size: 3
             )

    assert stats.total == 10
    assert stats.inserted == 10
    assert stats.invalid == 0
    assert stats.failed == 0
    assert stats.validation_errors == []
    assert length(all_products()) == 10
  end

  # ---------------------------------------------------------------------------
  # Changeset validation: invalid rows are skipped with line numbers
  # ---------------------------------------------------------------------------

  test "skips rows that fail changeset validation and reports line numbers" do
    header = ["external_id", "name", "price"]

    rows = [
      ["eid-1", "good product", "100"],
      # missing name → invalid (line 3)
      ["eid-2", "", "200"],
      # missing external_id → invalid (line 4)
      ["", "no id product", "300"],
      ["eid-4", "another good", "400"]
    ]

    path = tmp_path("validation.csv")
    write_csv!(path, header, rows)

    assert {:ok, stats} =
             CsvIngestion.ingest(TestRepo, Product, path,
               conflict_target: [:external_id],
               batch_size: 10
             )

    assert stats.total == 4
    assert stats.inserted == 2
    assert stats.invalid == 2
    assert stats.failed == 0

    # Verify line numbers are correct (header is line 1)
    error_lines = Enum.map(stats.validation_errors, &elem(&1, 0))
    assert 3 in error_lines
    assert 4 in error_lines

    assert length(all_products()) == 2
  end

  # ---------------------------------------------------------------------------
  # Batching: processes all valid records across multiple batches
  # ---------------------------------------------------------------------------

  test "respects batch_size: processes all valid records across multiple batches" do
    header = ["external_id", "name", "price"]
    rows = Enum.map(1..22, fn i -> ["b-#{i}", "batch #{i}", "#{i}"] end)

    path = tmp_path("batches.csv")
    write_csv!(path, header, rows)

    assert {:ok, stats} =
             CsvIngestion.ingest(TestRepo, Product, path,
               conflict_target: [:external_id],
               batch_size: 7
             )

    assert stats.total == 22
    assert stats.inserted == 22
    assert stats.failed == 0
    assert length(all_products()) == 22
  end

  # ---------------------------------------------------------------------------
  # Field mapping: custom header names → schema fields
  # ---------------------------------------------------------------------------

  test "uses field_mapping to map CSV headers to schema fields" do
    header = ["Product ID", "Product Name", "Unit Price"]

    rows = [
      ["eid-1", "Widget A", "500"],
      ["eid-2", "Widget B", "600"]
    ]

    path = tmp_path("mapping.csv")
    write_csv!(path, header, rows)

    mapping = %{
      "Product ID" => :external_id,
      "Product Name" => :name,
      "Unit Price" => :price
    }

    assert {:ok, stats} =
             CsvIngestion.ingest(TestRepo, Product, path,
               conflict_target: [:external_id],
               field_mapping: mapping
             )

    assert stats.total == 2
    assert stats.inserted == 2

    product = TestRepo.get_by!(Product, external_id: "eid-1")
    assert product.name == "Widget A"
    assert product.price == 500
  end

  # ---------------------------------------------------------------------------
  # Graceful error: file not found
  # ---------------------------------------------------------------------------

  test "returns {:error, :file_not_found} for missing file" do
    assert {:error, :file_not_found} =
             CsvIngestion.ingest(TestRepo, Product, "/no/such/file.csv")
  end

  # ---------------------------------------------------------------------------
  # Graceful error: empty file
  # ---------------------------------------------------------------------------

  test "returns {:error, :empty_file} for a zero-byte file" do
    path = tmp_path("empty.csv")
    File.write!(path, "")

    assert {:error, :empty_file} =
             CsvIngestion.ingest(TestRepo, Product, path)
  end

  # ---------------------------------------------------------------------------
  # Header-only file (valid, zero data rows)
  # ---------------------------------------------------------------------------

  test "handles a CSV file with only a header row" do
    path = tmp_path("header_only.csv")
    File.write!(path, "external_id,name,price\n")

    assert {:ok, stats} = CsvIngestion.ingest(TestRepo, Product, path)

    assert stats.total == 0
    assert stats.inserted == 0
    assert stats.invalid == 0
    assert stats.failed == 0
    assert all_products() == []
  end

  # ---------------------------------------------------------------------------
  # Partial failure: bad batch doesn't abort the rest
  # ---------------------------------------------------------------------------

  test "continues processing after a failed batch and reports failures" do
    # Insert valid rows first, then a batch that will fail due to NOT NULL
    # constraint (missing name), then more valid rows.
    header = ["external_id", "name", "price"]

    good_before = Enum.map(1..5, fn i -> ["pre-#{i}", "pre #{i}", "#{i}"] end)

    # These rows pass changeset validation (name present). To simulate a
    # DB-level batch failure, we seed these external_ids first, then ingest
    # the same ids with on_conflict: :raise so the conflicting batch fails
    # while the surrounding batches succeed.
    good_after = Enum.map(1..5, fn i -> ["post-#{i}", "post #{i}", "#{i}"] end)

    # First, seed some rows that will conflict
    seed_path = tmp_path("seed_csv.csv")
    conflict_rows = Enum.map(1..5, fn i -> ["conflict-#{i}", "old #{i}", "#{i}"] end)
    write_csv!(seed_path, header, conflict_rows)

    CsvIngestion.ingest(TestRepo, Product, seed_path,
      conflict_target: [:external_id],
      on_conflict: :nothing
    )

    # Now ingest: good_before + conflict rows + good_after, with on_conflict: :raise
    # The conflict batch should fail, others succeed.
    all_rows = good_before ++ conflict_rows ++ good_after
    path = tmp_path("partial_fail.csv")
    write_csv!(path, header, all_rows)

    assert {:ok, stats} =
             CsvIngestion.ingest(TestRepo, Product, path,
               conflict_target: [:external_id],
               on_conflict: :raise,
               batch_size: 5
             )

    assert stats.total == 15
    assert stats.failed == 5
    assert stats.inserted == 10
  end

  test "emits an info log line with running totals even for batches that fail" do
    defmodule RaisingProbeRepo do
      def insert_all(_schema, _entries, _opts), do: raise("boom")
    end

    header = ["external_id", "name", "price"]
    rows = Enum.map(1..4, fn i -> ["fail-#{i}", "fail #{i}", "#{i}"] end)

    path = tmp_path("info_per_failed_batch.csv")
    write_csv!(path, header, rows)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:ok, stats} =
                 CsvIngestion.ingest(RaisingProbeRepo, Product, path, batch_size: 2)

        assert stats.total == 4
        assert stats.failed == 4
        assert stats.inserted == 0
      end)

    info_lines =
      log
      |> String.split("\n")
      |> Enum.filter(&String.contains?(&1, "[info]"))

    # Two batches were processed, so at least two per-batch info lines are owed.
    assert length(info_lines) >= 2
  end

  test "defaults batch_size to 500 valid records per insert_all call" do
    defmodule DefaultBatchProbeRepo do
      def insert_all(_schema, entries, _opts) do
        send(Process.whereis(:csv_default_batch_probe), {:batch, length(entries)})
        {length(entries), nil}
      end
    end

    Process.register(self(), :csv_default_batch_probe)

    header = ["external_id", "name", "price"]
    rows = Enum.map(1..501, fn i -> ["d-#{i}", "default #{i}", "#{i}"] end)

    path = tmp_path("default_batch_size.csv")
    write_csv!(path, header, rows)

    assert {:ok, stats} = CsvIngestion.ingest(DefaultBatchProbeRepo, Product, path)

    assert_receive {:batch, 500}
    assert_receive {:batch, 1}
    refute_receive {:batch, _}

    assert stats.total == 501
    assert stats.inserted == 501
  end

  test "passes the documented on_conflict and conflict_target defaults to insert_all" do
    defmodule DefaultOptsProbeRepo do
      def insert_all(_schema, entries, opts) do
        send(Process.whereis(:csv_default_opts_probe), {:opts, opts})
        {length(entries), nil}
      end
    end

    Process.register(self(), :csv_default_opts_probe)

    header = ["external_id", "name", "price"]
    rows = [["opt-1", "opt one", "10"]]

    path = tmp_path("default_opts.csv")
    write_csv!(path, header, rows)

    assert {:ok, _stats} = CsvIngestion.ingest(DefaultOptsProbeRepo, Product, path)

    assert_receive {:opts, opts}
    assert Keyword.get(opts, :on_conflict) == :nothing
    assert Keyword.get(opts, :conflict_target) == :nothing
  end

  test "injects inserted_at and updated_at timestamps into inserted rows" do
    header = ["external_id", "name", "price"]
    rows = [["ts-1", "timestamped", "42"]]

    path = tmp_path("timestamps.csv")
    write_csv!(path, header, rows)

    assert {:ok, stats} =
             CsvIngestion.ingest(TestRepo, Product, path, conflict_target: [:external_id])

    assert stats.inserted == 1

    product = TestRepo.get_by!(Product, external_id: "ts-1")
    assert product.inserted_at != nil
    assert product.updated_at != nil
  end

  test "converts headers to snake_case atoms when no field_mapping is given" do
    header = ["External ID", "Name", "Price"]
    rows = [["snake-1", "Snake Widget", "700"]]

    path = tmp_path("snake_headers.csv")
    write_csv!(path, header, rows)

    assert {:ok, stats} =
             CsvIngestion.ingest(TestRepo, Product, path, conflict_target: [:external_id])

    assert stats.total == 1
    assert stats.inserted == 1
    assert stats.invalid == 0

    product = TestRepo.get_by!(Product, external_id: "snake-1")
    assert product.name == "Snake Widget"
    assert product.price == 700
  end

  test "reports the changeset errors keyword list for each invalid row" do
    header = ["external_id", "name", "price"]
    rows = [["eid-1", "", "100"]]

    path = tmp_path("error_payload.csv")
    write_csv!(path, header, rows)

    assert {:ok, stats} =
             CsvIngestion.ingest(TestRepo, Product, path, conflict_target: [:external_id])

    assert stats.invalid == 1
    assert [{2, errors}] = stats.validation_errors
    assert Keyword.keyword?(errors)
    assert {msg, meta} = Keyword.fetch!(errors, :name)
    assert is_binary(msg)
    assert is_list(meta)
  end
end
