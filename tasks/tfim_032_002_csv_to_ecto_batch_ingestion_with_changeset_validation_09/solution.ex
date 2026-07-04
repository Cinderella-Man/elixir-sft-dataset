  test "continues processing after a failed batch and reports failures" do
    # Insert valid rows first, then a batch that will fail due to NOT NULL
    # constraint (missing name), then more valid rows.
    header = ["external_id", "name", "price"]

    good_before = Enum.map(1..5, fn i -> ["pre-#{i}", "pre #{i}", "#{i}"] end)

    # These rows pass changeset validation (name present) but will fail at DB
    # level if we somehow bypass the changeset. To simulate a DB-level failure
    # in a batch, we use the conflict_target mechanism: we seed duplicates.
    # Actually, let's do it differently — we insert rows first, then try
    # inserting the same external_ids with on_conflict: :raise.
    good_after = Enum.map(1..5, fn i -> ["post-#{i}", "post #{i}", "#{i}"] end)

    # First, seed some rows that will conflict
    seed_path = tmp_path("seed_csv.csv")
    conflict_rows = Enum.map(1..5, fn i -> ["conflict-#{i}", "old #{i}", "#{i}"] end)
    write_csv!(seed_path, header, conflict_rows)
    CsvIngestion.ingest(TestRepo, Product, seed_path,
      conflict_target: [:external_id], on_conflict: :nothing)

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