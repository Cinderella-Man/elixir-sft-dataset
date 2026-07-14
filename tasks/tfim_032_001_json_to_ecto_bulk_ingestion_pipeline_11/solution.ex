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