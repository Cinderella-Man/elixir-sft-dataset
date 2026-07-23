# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

```elixir
defmodule CsvIngestion do
  @moduledoc """
  Reads a CSV file, validates each row via an Ecto changeset, and batch-inserts
  valid rows into the database.

  Invalid rows are collected with their line numbers and changeset errors so the
  caller can report validation failures without aborting the entire import.

  ## Example

      CsvIngestion.ingest(MyApp.Repo, MyApp.Product, "/tmp/products.csv",
        batch_size:     1_000,
        on_conflict:    :nothing,
        conflict_target: [:external_id],
        field_mapping:  %{"Product ID" => :external_id, "Product Name" => :name}
      )
      #=> {:ok, %{total: 5000, inserted: 4980, invalid: 18, failed: 0,
      #=>         validation_errors: [{3, [name: {"can't be blank", ...}]}, ...]}}
  """

  require Logger

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  @type repo :: module()
  @type schema :: module()
  @type stats :: %{
          total: integer(),
          inserted: integer(),
          invalid: integer(),
          failed: integer(),
          validation_errors: [{pos_integer(), keyword()}]
        }
  @type ingest_opts :: [
          batch_size: pos_integer(),
          on_conflict: atom() | keyword(),
          conflict_target: atom() | [atom()],
          field_mapping: map() | nil
        ]

  # ---------------------------------------------------------------------------
  # Defaults
  # ---------------------------------------------------------------------------

  @default_batch_size 500
  @default_on_conflict :nothing
  @default_conflict_target []

  # ---------------------------------------------------------------------------
  # CSV parser definition
  # ---------------------------------------------------------------------------

  NimbleCSV.define(CsvIngestion.Parser, separator: ",", escape: "\"")

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Ingests records from a CSV file into the database.

  ## Parameters

    - `repo`      – An Ecto repository module (e.g. `MyApp.Repo`).
    - `schema`    – An Ecto schema module that also exposes `changeset/2`.
    - `file_path` – Path to a UTF-8 CSV file with a header row.
    - `opts`      – Keyword list; see module doc for accepted keys.

  ## Return values

    - `{:ok, stats}` – Returned when the file was read and parsed successfully,
                       even if some rows were invalid or some batches failed.
    - `{:error, :file_not_found}` – The file does not exist.
    - `{:error, :empty_file}`     – The file is 0 bytes.
  """
  @spec ingest(repo(), schema(), String.t(), ingest_opts()) ::
          {:ok, stats()} | {:error, :file_not_found | :empty_file}
  def ingest(repo, schema, file_path, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    on_conflict = Keyword.get(opts, :on_conflict, @default_on_conflict)
    conflict_target = Keyword.get(opts, :conflict_target, @default_conflict_target)
    field_mapping = Keyword.get(opts, :field_mapping, nil)

    with :ok <- check_file(file_path),
         {:ok, rows} <- parse_csv(file_path) do
      cfg = %{
        batch_size: batch_size,
        on_conflict: on_conflict,
        conflict_target: conflict_target
      }

      {:ok, process_rows(repo, schema, rows, field_mapping, cfg)}
    end
  end

  # ---------------------------------------------------------------------------
  # File checks
  # ---------------------------------------------------------------------------

  @spec check_file(String.t()) :: :ok | {:error, :file_not_found | :empty_file}
  defp check_file(path) do
    cond do
      not File.exists?(path) ->
        Logger.error("[CsvIngestion] File not found: #{inspect(path)}")
        {:error, :file_not_found}

      File.stat!(path).size == 0 ->
        Logger.error("[CsvIngestion] File is empty: #{inspect(path)}")
        {:error, :empty_file}

      true ->
        :ok
    end
  end

  # ---------------------------------------------------------------------------
  # CSV parsing
  # ---------------------------------------------------------------------------

  @spec parse_csv(String.t()) :: {:ok, {[String.t()], [[String.t()]]}}
  defp parse_csv(path) do
    raw = File.read!(path)

    # NimbleCSV.parse_string with skip_headers: false returns every row as a
    # list of fields; the first row is split off as the header list.
    parsed =
      raw
      |> CsvIngestion.Parser.parse_string(skip_headers: false)
      |> then(fn
        [] -> {[], []}
        [hdr | rows] -> {hdr, rows}
      end)

    case parsed do
      {_headers, _data} = pair -> {:ok, pair}
    end
  end

  # ---------------------------------------------------------------------------
  # Row processing
  # ---------------------------------------------------------------------------

  @spec process_rows(repo(), schema(), {[String.t()], [[String.t()]]}, map() | nil, map()) ::
          stats()
  defp process_rows(repo, schema, {headers, data_rows}, field_mapping, cfg) do
    atom_headers = map_headers(headers, field_mapping)
    schema_keys = schema_field_set(schema)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    total = length(data_rows)

    # Validate each row via changeset; split into valid and invalid.
    {valid_rows, validation_errors} =
      data_rows
      # line 2 is the first data row
      |> Enum.with_index(2)
      |> Enum.reduce({[], []}, fn {cells, line_num}, {valid_acc, err_acc} ->
        attrs = build_attrs(cells, atom_headers, schema_keys)
        changeset = schema.changeset(struct(schema), attrs)

        if changeset.valid? do
          row =
            changeset.changes
            |> maybe_put_ts(:inserted_at, now, schema_keys)
            |> maybe_put_ts(:updated_at, now, schema_keys)

          {[row | valid_acc], err_acc}
        else
          {valid_acc, [{line_num, changeset.errors} | err_acc]}
        end
      end)

    valid_rows = Enum.reverse(valid_rows)
    validation_errors = Enum.reverse(validation_errors)
    invalid_count = length(validation_errors)

    # Batch-insert valid rows.
    initial_acc = %{
      total: total,
      inserted: 0,
      invalid: invalid_count,
      failed: 0,
      validation_errors: validation_errors
    }

    stats =
      valid_rows
      |> Enum.chunk_every(cfg.batch_size)
      |> Enum.reduce(initial_acc, fn batch, acc ->
        process_batch(repo, schema, batch, cfg, acc)
      end)

    Logger.info("[CsvIngestion] Finished. Final stats: #{format_stats(stats)}")
    stats
  end

  # ---------------------------------------------------------------------------
  # Header mapping
  # ---------------------------------------------------------------------------

  @spec map_headers([String.t()], map() | nil) :: [atom()]
  defp map_headers(headers, nil) do
    Enum.map(headers, fn h ->
      h
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/\s+/, "_")
      |> String.to_atom()
    end)
  end

  defp map_headers(headers, mapping) when is_map(mapping) do
    Enum.map(headers, fn h ->
      trimmed = String.trim(h)
      Map.get(mapping, trimmed, default_atom(trimmed))
    end)
  end

  defp default_atom(header) do
    header
    |> String.downcase()
    |> String.replace(~r/\s+/, "_")
    |> String.to_atom()
  end

  # ---------------------------------------------------------------------------
  # Attribute building
  # ---------------------------------------------------------------------------

  @spec build_attrs([String.t()], [atom()], MapSet.t()) :: map()
  defp build_attrs(cells, atom_headers, schema_keys) do
    atom_headers
    |> Enum.zip(cells)
    |> Enum.filter(fn {k, _v} -> MapSet.member?(schema_keys, Atom.to_string(k)) end)
    |> Enum.map(fn {k, v} -> {k, normalize_value(v)} end)
    |> Map.new()
  end

  defp normalize_value(""), do: nil
  defp normalize_value(v), do: String.trim(v)

  # ---------------------------------------------------------------------------
  # Schema introspection
  # ---------------------------------------------------------------------------

  @spec schema_field_set(module()) :: MapSet.t(String.t())
  defp schema_field_set(schema) do
    schema.__schema__(:fields)
    |> Enum.map(&Atom.to_string/1)
    |> MapSet.new()
  end

  # ---------------------------------------------------------------------------
  # Timestamp injection
  # ---------------------------------------------------------------------------

  @spec maybe_put_ts(map(), atom(), NaiveDateTime.t(), MapSet.t()) :: map()
  defp maybe_put_ts(row, field, value, schema_keys) do
    if MapSet.member?(schema_keys, Atom.to_string(field)) do
      Map.put_new(row, field, value)
    else
      row
    end
  end

  # ---------------------------------------------------------------------------
  # Batch processing
  # ---------------------------------------------------------------------------

  @spec process_batch(repo(), schema(), [map()], map(), stats()) :: stats()
  defp process_batch(repo, schema, batch, cfg, acc) do
    # Ecto forbids `:conflict_target` together with `on_conflict: :raise` (the
    # default), so only attach a conflict target for the conflict-handling modes.
    # With `:raise`, a duplicate key surfaces as a normal constraint error (caught
    # below and counted against this batch).
    insert_opts =
      case {cfg.on_conflict, cfg.conflict_target} do
        {:raise, _} ->
          [on_conflict: :raise]

        # An empty conflict target cannot be handed to Ecto (it rejects the
        # wrapped [:nothing]/[] as an unknown column) — omit the option, so
        # a default-opts ingest actually inserts instead of failing every
        # batch inside the rescue.
        {other, []} ->
          [on_conflict: other]

        {other, target} ->
          [on_conflict: other, conflict_target: target]
      end

    batch_size = length(batch)

    try do
      {count, _} = repo.insert_all(schema, batch, insert_opts)

      new_acc = %{acc | inserted: acc.inserted + count}

      Logger.info(
        "[CsvIngestion] Batch done — " <>
          "size: #{batch_size}, inserted: #{count}. " <>
          "Running totals — #{format_stats(new_acc)}"
      )

      new_acc
    rescue
      error ->
        Logger.error(
          "[CsvIngestion] Batch failed (#{batch_size} records skipped): " <>
            Exception.format(:error, error, __STACKTRACE__)
        )

        %{acc | failed: acc.failed + batch_size}
    catch
      kind, reason ->
        Logger.error(
          "[CsvIngestion] Batch failed with #{kind} " <>
            "(#{batch_size} records skipped): #{inspect(reason)}"
        )

        %{acc | failed: acc.failed + batch_size}
    end
  end

  # ---------------------------------------------------------------------------
  # Formatting
  # ---------------------------------------------------------------------------

  @spec format_stats(stats()) :: String.t()
  defp format_stats(%{total: t, inserted: i, invalid: inv, failed: f}) do
    "total=#{t} inserted=#{i} invalid=#{inv} failed=#{f}"
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
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
    # TODO
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

  test "DEFAULT options actually insert (empty conflict target is omitted)" do
    header = ["external_id", "name", "price"]
    rows = Enum.map(1..4, fn i -> ["def-#{i}", "product #{i}", "#{i * 10}"] end)

    path = tmp_path("default_opts.csv")
    write_csv!(path, header, rows)

    # No conflict options at all: the empty default target must be omitted
    # from insert_all — a naive pass-through fails every batch in the rescue.
    assert {:ok, stats} = CsvIngestion.ingest(TestRepo, Product, path)
    assert stats.inserted == 4
    assert stats.failed == 0
  end
end
```
