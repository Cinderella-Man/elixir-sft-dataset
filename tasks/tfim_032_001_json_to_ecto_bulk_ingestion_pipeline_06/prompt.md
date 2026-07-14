# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule DataIngestion do
  @moduledoc """
  Reads a large JSON array file and upserts its records into a database table
  via Ecto in configurable batches.

  `Jason.decode/1` always returns string-keyed maps.  This module converts
  those keys to atoms (using only fields declared on the schema) and injects
  `inserted_at` / `updated_at` timestamps before calling `insert_all`, because
  `insert_all` bypasses Ecto callbacks and will not set timestamps on its own.

  ## Example

      DataIngestion.ingest(MyApp.Repo, MyApp.Product, "/tmp/products.json",
        batch_size:       1_000,
        on_conflict:      :replace_all,
        conflict_target:  [:external_id],
        returning:        true
      )
      #=> {:ok, %{total: 42_000, inserted: 40_100, updated: 1_900, failed: 0}}
  """

  require Logger

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  @type repo :: module()
  @type schema :: module()
  @type file_path :: String.t()
  @type stats :: %{total: integer(), inserted: integer(), updated: integer(), failed: integer()}
  @type ingest_opts :: [
          batch_size: pos_integer(),
          on_conflict: atom() | keyword(),
          conflict_target: atom() | [atom()],
          returning: boolean()
        ]

  # ---------------------------------------------------------------------------
  # Defaults
  # ---------------------------------------------------------------------------

  @default_batch_size 500
  @default_on_conflict :replace_all
  @default_conflict_target []
  @default_returning true

  # Tolerance window (seconds) used to tell a fresh INSERT from an UPDATE when
  # comparing the returned inserted_at / updated_at timestamps.
  @insert_window_seconds 1

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Ingests records from a JSON array file into the database.

  ## Parameters

    - `repo`      – An Ecto repository module (e.g. `MyApp.Repo`).
    - `schema`    – An Ecto schema module whose table will receive the rows.
    - `file_path` – Absolute or relative path to a UTF-8 JSON file whose
                    top-level value is an array of objects.
    - `opts`      – Keyword list; see module doc for accepted keys.

  ## Return values

    - `{:ok, stats}` – Always returned when the file was read and parsed
                       successfully, even if individual batches failed.
    - `{:error, :file_not_found}` – The file does not exist or is unreadable.
    - `{:error, :invalid_json}`   – The file contents are not valid JSON.
    - `{:error, :not_a_list}`     – The JSON root value is not an array.
    - `{:error, :conflict_target_required}` – `on_conflict` is the default
      `:replace_all` but no `:conflict_target` was given (Ecto requires the
      conflict columns to build an upsert).
  """
  @spec ingest(repo(), schema(), file_path(), ingest_opts()) ::
          {:ok, stats()}
          | {:error, :file_not_found | :invalid_json | :not_a_list | :conflict_target_required}
  def ingest(repo, schema, file_path, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    on_conflict = Keyword.get(opts, :on_conflict, @default_on_conflict)
    conflict_target = Keyword.get(opts, :conflict_target, @default_conflict_target)
    returning = Keyword.get(opts, :returning, @default_returning)

    with {:ok, raw} <- read_file(file_path),
         {:ok, parsed} <- parse_json(raw),
         {:ok, records} <- validate_list(parsed),
         :ok <- validate_conflict_opts(records, on_conflict, conflict_target) do
      cfg = %{
        batch_size: batch_size,
        on_conflict: on_conflict,
        conflict_target: conflict_target,
        returning: returning
      }

      {:ok, process_batches(repo, schema, records, cfg)}
    end
  end

  # ---------------------------------------------------------------------------
  # File I/O and validation
  # ---------------------------------------------------------------------------

  @spec read_file(file_path()) :: {:ok, binary()} | {:error, :file_not_found}
  defp read_file(path) do
    case File.read(path) do
      {:ok, contents} ->
        {:ok, contents}

      {:error, reason} ->
        Logger.error("[DataIngestion] Could not read file #{inspect(path)}: #{inspect(reason)}")
        {:error, :file_not_found}
    end
  end

  @spec parse_json(binary()) :: {:ok, term()} | {:error, :invalid_json}
  defp parse_json(raw) do
    case Jason.decode(raw) do
      {:ok, value} ->
        {:ok, value}

      {:error, reason} ->
        Logger.error("[DataIngestion] JSON parse error: #{inspect(reason)}")
        {:error, :invalid_json}
    end
  end

  @spec validate_list(term()) :: {:ok, list()} | {:error, :not_a_list}
  defp validate_list(value) when is_list(value), do: {:ok, value}

  defp validate_list(value) do
    Logger.error("[DataIngestion] Expected a JSON array, got: #{inspect(value, limit: 5)}")
    {:error, :not_a_list}
  end

  # ---------------------------------------------------------------------------
  # Batch processing
  # ---------------------------------------------------------------------------

  @spec process_batches(repo(), schema(), list(), map()) :: stats()
  defp process_batches(repo, schema, records, cfg) do
    total = length(records)
    schema_keys = schema_field_set(schema)
    initial_acc = %{total: total, inserted: 0, updated: 0, failed: 0}

    stats =
      records
      |> Enum.chunk_every(cfg.batch_size)
      |> Enum.reduce(initial_acc, fn raw_batch, acc ->
        # Prepare rows: atomise keys, drop unknown fields, inject timestamps.
        prepared = prepare_rows(raw_batch, schema_keys)
        process_batch(repo, schema, prepared, length(raw_batch), cfg, acc)
      end)

    Logger.info("[DataIngestion] Finished. Final stats: #{format_stats(stats)}")
    stats
  end

  @spec process_batch(repo(), schema(), list(), non_neg_integer(), map(), stats()) :: stats()
  defp process_batch(repo, schema, prepared_batch, raw_count, cfg, acc) do
    insert_opts = build_insert_opts(cfg)

    try do
      {_count, returned_rows} = repo.insert_all(schema, prepared_batch, insert_opts)
      {ins, upd} = classify_rows(returned_rows, raw_count, cfg.returning)

      new_acc = %{acc | inserted: acc.inserted + ins, updated: acc.updated + upd}

      Logger.info(
        "[DataIngestion] Batch done — " <>
          "size: #{raw_count}, inserted: #{ins}, updated: #{upd}. " <>
          "Running totals — #{format_stats(new_acc)}"
      )

      new_acc
    rescue
      error ->
        Logger.error(
          "[DataIngestion] Batch failed (#{raw_count} records skipped): " <>
            Exception.format(:error, error, __STACKTRACE__)
        )

        %{acc | failed: acc.failed + raw_count}
    catch
      kind, reason ->
        Logger.error(
          "[DataIngestion] Batch failed with #{kind} " <>
            "(#{raw_count} records skipped): #{inspect(reason)}"
        )

        %{acc | failed: acc.failed + raw_count}
    end
  end

  # ---------------------------------------------------------------------------
  # Row preparation
  # ---------------------------------------------------------------------------

  # Returns the set of field name *strings* declared on the schema, excluding
  # virtual fields.  We compare against strings (not atoms) because that is
  # what Jason gives us, avoiding the need for String.to_atom/1 on arbitrary
  # untrusted input.
  @spec schema_field_set(schema()) :: MapSet.t(String.t())
  defp schema_field_set(schema) do
    schema.__schema__(:fields)
    |> Enum.map(&Atom.to_string/1)
    |> MapSet.new()
  end

  # Converts a list of string-keyed JSON maps into the atom-keyed maps that
  # `insert_all` expects, filtering to only the columns the schema knows about
  # and injecting `inserted_at` / `updated_at` when the schema declares them.
  @spec prepare_rows(list(map()), MapSet.t(String.t())) :: list(map())
  defp prepare_rows(raw_rows, schema_keys) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Enum.map(raw_rows, fn row ->
      base =
        row
        |> Enum.filter(fn {k, _v} -> MapSet.member?(schema_keys, k) end)
        |> Enum.map(fn {k, v} ->
          # Safe: the atom already exists because it was interned when the
          # schema module was compiled.
          {String.to_existing_atom(k), v}
        end)
        |> Map.new()

      # Only inject timestamps if the schema actually has them; avoids errors
      # on schemas that do not call `timestamps()`.
      base
      |> maybe_put_new(:inserted_at, now, schema_keys)
      |> maybe_put_new(:updated_at, now, schema_keys)
    end)
  end

  @spec maybe_put_new(map(), atom(), term(), MapSet.t(String.t())) :: map()
  defp maybe_put_new(row, field, value, schema_keys) do
    if MapSet.member?(schema_keys, Atom.to_string(field)) do
      Map.put_new(row, field, value)
    else
      row
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # `:replace_all` cannot be built without knowing which columns identify the
  # conflict — surfaced as one caller error before any batch is attempted,
  # rather than one opaque Ecto raise per batch. File/JSON problems are
  # reported first, and an empty array has no upsert to build, so both keep
  # their own documented results.
  @spec validate_conflict_opts([map()], atom() | keyword(), atom() | [atom()]) ::
          :ok | {:error, :conflict_target_required}
  defp validate_conflict_opts([], _on_conflict, _target), do: :ok

  defp validate_conflict_opts([_ | _], :replace_all, []),
    do: {:error, :conflict_target_required}

  defp validate_conflict_opts(_records, _on_conflict, _target), do: :ok

  @spec build_insert_opts(map()) :: keyword()
  defp build_insert_opts(cfg) do
    # An empty conflict_target means "none": the option is omitted rather
    # than passed — Ecto accepts only column lists / fragments there, and
    # on_conflict values like :raise or :nothing need no target at all.
    base =
      if cfg.conflict_target == [] do
        [on_conflict: cfg.on_conflict]
      else
        [on_conflict: cfg.on_conflict, conflict_target: cfg.conflict_target]
      end

    if cfg.returning, do: Keyword.put(base, :returning, true), else: base
  end

  # Determines how many rows in a batch were inserted vs updated.
  #
  # When `returning: true`, Ecto gives back one struct / map per affected row.
  # A row is treated as a fresh insert when its `inserted_at` and `updated_at`
  # timestamps are equal within @insert_window_seconds (both were written in
  # this call).  A row whose `updated_at` trails `inserted_at` was overwriting
  # a pre-existing record whose original `inserted_at` was preserved.
  #
  # When `returning: false`, `insert_all` returns `{count, nil}`, so we cannot
  # distinguish inserts from updates — credit everything to `:inserted`.
  @spec classify_rows(list() | nil, non_neg_integer(), boolean()) ::
          {non_neg_integer(), non_neg_integer()}
  defp classify_rows(_rows, count, false), do: {count, 0}
  defp classify_rows(nil, count, _ret), do: {count, 0}

  defp classify_rows(rows, _count, true) do
    Enum.reduce(rows, {0, 0}, fn row, {ins, upd} ->
      if timestamps_equal?(get_ts(row, :inserted_at), get_ts(row, :updated_at)) do
        {ins + 1, upd}
      else
        {ins, upd + 1}
      end
    end)
  end

  # Accepts both atom-keyed structs/maps and string-keyed plain maps.
  @spec get_ts(map() | struct(), atom()) :: NaiveDateTime.t() | DateTime.t() | nil
  defp get_ts(row, field) when is_map(row) do
    Map.get(row, field) || Map.get(row, Atom.to_string(field))
  end

  @spec timestamps_equal?(term(), term()) :: boolean()
  defp timestamps_equal?(nil, _), do: false
  defp timestamps_equal?(_, nil), do: false

  defp timestamps_equal?(%NaiveDateTime{} = a, %NaiveDateTime{} = b),
    do: abs(NaiveDateTime.diff(a, b, :second)) <= @insert_window_seconds

  defp timestamps_equal?(%DateTime{} = a, %DateTime{} = b),
    do: abs(DateTime.diff(a, b, :second)) <= @insert_window_seconds

  defp timestamps_equal?(_, _), do: false

  @spec format_stats(stats()) :: String.t()
  defp format_stats(%{total: t, inserted: i, updated: u, failed: f}),
    do: "total=#{t} inserted=#{i} updated=#{u} failed=#{f}"
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule DataIngestionTest do
  use ExUnit.Case, async: false

  # ---------------------------------------------------------------------------
  # Minimal in-memory Ecto setup
  # ---------------------------------------------------------------------------

  # We use the Ecto sandbox with an SQLite3 (or PG) test repo.
  # The schema below must match whatever table your migration creates.

  defmodule TestRepo do
    use Ecto.Repo, otp_app: :data_ingestion, adapter: Ecto.Adapters.SQLite3
  end

  defmodule Widget do
    use Ecto.Schema

    @primary_key {:id, :id, autogenerate: true}

    schema "widgets" do
      field(:external_id, :string)
      field(:name, :string)
      field(:value, :integer)
      timestamps()
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp write_json!(path, data) do
    File.write!(path, Jason.encode!(data))
  end

  defp tmp_path(name),
    do:
      Path.join(
        System.tmp_dir!(),
        "#{System.pid()}_#{System.unique_integer([:positive])}_#{name}"
      )

  defp all_widgets, do: TestRepo.all(Widget)

  # ---------------------------------------------------------------------------
  # Setup / teardown
  # ---------------------------------------------------------------------------

  setup_all do
    Application.put_env(:data_ingestion, DataIngestionTest.TestRepo,
      database: ":memory:",
      pool_size: 1
    )

    {:ok, _} = DataIngestionTest.TestRepo.start_link()

    DataIngestionTest.TestRepo.query!(
      """
      CREATE TABLE widgets (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        external_id TEXT    UNIQUE,
        name        TEXT    NOT NULL,
        value       INTEGER,
        inserted_at TEXT    NOT NULL,
        updated_at  TEXT    NOT NULL
      )
      """,
      []
    )

    :ok
  end

  setup do
    # Truncate table before each test
    TestRepo.delete_all(Widget)
    :ok
  end

  # ---------------------------------------------------------------------------
  # Happy-path: fresh inserts
  # ---------------------------------------------------------------------------

  test "inserts all records from a simple JSON file" do
    records =
      Enum.map(1..10, fn i ->
        %{"external_id" => "eid-#{i}", "name" => "widget #{i}", "value" => i}
      end)

    path = tmp_path("fresh_insert.json")
    write_json!(path, records)

    assert {:ok, stats} =
             DataIngestion.ingest(TestRepo, Widget, path,
               conflict_target: [:external_id],
               batch_size: 3
             )

    assert stats.total == 10
    assert stats.inserted == 10
    assert stats.updated == 0
    assert stats.failed == 0
    assert length(all_widgets()) == 10
  end

  # ---------------------------------------------------------------------------
  # Upsert: duplicates become updates
  # ---------------------------------------------------------------------------

  test "updates existing records on conflict" do
    # Seed 5 rows
    seed =
      Enum.map(1..5, fn i ->
        %{"external_id" => "eid-#{i}", "name" => "old #{i}", "value" => 0}
      end)

    path = tmp_path("seed.json")
    write_json!(path, seed)
    DataIngestion.ingest(TestRepo, Widget, path, conflict_target: [:external_id])

    # Sleep long enough that the second ingest's timestamp (truncated to seconds)
    # differs from the seed's inserted_at by > @insert_window_seconds (1 s), so the
    # solution's timestamp-based classifier can tell inserts from updates.
    Process.sleep(2000)

    # Now run again: same 5 external_ids + 5 new ones
    records =
      Enum.map(1..10, fn i ->
        %{"external_id" => "eid-#{i}", "name" => "new #{i}", "value" => i * 10}
      end)

    write_json!(path, records)

    assert {:ok, stats} =
             DataIngestion.ingest(TestRepo, Widget, path,
               conflict_target: [:external_id],
               # Preserve the original inserted_at so the classifier can distinguish
               # fresh inserts (inserted_at ≈ updated_at) from updates (inserted_at
               # is 2+ seconds older than updated_at).
               on_conflict: {:replace_all_except, [:inserted_at]},
               batch_size: 4
             )

    assert stats.total == 10
    assert stats.failed == 0
    # 5 new + 5 existing  → inserts + updates = 10
    assert stats.inserted + stats.updated == 10
    assert stats.updated >= 5

    # Values in DB should reflect the new run
    widget = TestRepo.get_by!(Widget, external_id: "eid-1")
    assert widget.name == "new 1"
    assert widget.value == 10
  end

  # ---------------------------------------------------------------------------
  # Batching
  # ---------------------------------------------------------------------------

  test "respects batch_size: processes all records across multiple batches" do
    records =
      Enum.map(1..25, fn i ->
        %{"external_id" => "b-#{i}", "name" => "b #{i}", "value" => i}
      end)

    path = tmp_path("batches.json")
    write_json!(path, records)

    assert {:ok, stats} =
             DataIngestion.ingest(TestRepo, Widget, path,
               conflict_target: [:external_id],
               batch_size: 7
             )

    assert stats.total == 25
    assert stats.inserted == 25
    assert stats.failed == 0
    assert length(all_widgets()) == 25
  end

  # ---------------------------------------------------------------------------
  # Graceful error: file not found
  # ---------------------------------------------------------------------------

  test "returns {:error, :file_not_found} for missing file" do
    assert {:error, :file_not_found} =
             DataIngestion.ingest(TestRepo, Widget, "/no/such/file.json")
  end

  # ---------------------------------------------------------------------------
  # Graceful error: malformed JSON
  # ---------------------------------------------------------------------------

  test "returns {:error, :invalid_json} for a malformed JSON file" do
    # TODO
  end

  # ---------------------------------------------------------------------------
  # Graceful error: valid JSON but not an array
  # ---------------------------------------------------------------------------

  test "returns {:error, :not_a_list} when the JSON root is not an array" do
    path = tmp_path("object.json")
    write_json!(path, %{"key" => "value"})

    assert {:error, :not_a_list} =
             DataIngestion.ingest(TestRepo, Widget, path)
  end

  # ---------------------------------------------------------------------------
  # Partial failure: bad batch doesn't abort the rest
  # ---------------------------------------------------------------------------

  test "continues processing after a failed batch and reports failures" do
    # 10 valid records + 1 batch that will fail due to a nil non-nullable field,
    # then 10 more valid records.
    # We simulate a bad batch by monkey-patching — instead, we pass records
    # missing a required DB field in one specific batch.
    # Here we rely on the implementation failing gracefully.

    good_before =
      Enum.map(1..10, fn i ->
        %{"external_id" => "pre-#{i}", "name" => "pre #{i}", "value" => i}
      end)

    # These records are missing the "name" field; if "name" has a NOT NULL
    # constraint they will cause the batch to fail.
    bad_batch =
      Enum.map(1..5, fn i ->
        %{"external_id" => "bad-#{i}", "value" => i}
      end)

    good_after =
      Enum.map(1..10, fn i ->
        %{"external_id" => "post-#{i}", "name" => "post #{i}", "value" => i}
      end)

    path = tmp_path("partial_fail.json")
    write_json!(path, good_before ++ bad_batch ++ good_after)

    # batch_size=5 means batches are:
    #   [pre-1..5], [pre-6..10], [bad-1..5], [post-1..5], [post-6..10]
    assert {:ok, stats} =
             DataIngestion.ingest(TestRepo, Widget, path,
               conflict_target: [:external_id],
               batch_size: 5
             )

    assert stats.total == 25
    # the bad batch
    assert stats.failed == 5
    assert stats.inserted == 20
    assert length(all_widgets()) == 20
  end

  # ---------------------------------------------------------------------------
  # Empty file (valid JSON empty array)
  # ---------------------------------------------------------------------------

  test "handles an empty JSON array gracefully" do
    path = tmp_path("empty.json")
    write_json!(path, [])

    assert {:ok, stats} = DataIngestion.ingest(TestRepo, Widget, path)

    assert stats == %{total: 0, inserted: 0, updated: 0, failed: 0}
    assert all_widgets() == []
  end

  # ---------------------------------------------------------------------------
  # Conflict options: the default :replace_all requires a conflict_target
  # ---------------------------------------------------------------------------

  test "default options without a conflict_target are rejected up front" do
    path = tmp_path("defaults_no_target.json")
    write_json!(path, [%{"external_id" => "nt-1", "name" => "a", "value" => 1}])

    assert {:error, :conflict_target_required} =
             DataIngestion.ingest(TestRepo, Widget, path)

    assert all_widgets() == []
  end

  test "on_conflict: :nothing needs no conflict_target and skips duplicates" do
    path = tmp_path("nothing_fresh.json")
    write_json!(path, [%{"external_id" => "skip-1", "name" => "orig", "value" => 1}])

    assert {:ok, %{inserted: 1, failed: 0}} =
             DataIngestion.ingest(TestRepo, Widget, path, on_conflict: :nothing)

    # The same external_id again is skipped, not replaced, and nothing fails.
    path2 = tmp_path("nothing_dup.json")
    write_json!(path2, [%{"external_id" => "skip-1", "name" => "clobber", "value" => 9}])

    assert {:ok, stats} =
             DataIngestion.ingest(TestRepo, Widget, path2, on_conflict: :nothing)

    assert stats.failed == 0
    assert [%{name: "orig", value: 1}] = all_widgets()
  end
end
```
