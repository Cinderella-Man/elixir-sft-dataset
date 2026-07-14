  test "default options without a conflict_target are rejected up front" do
    path = tmp_path("defaults_no_target.json")
    write_json!(path, [%{"external_id" => "nt-1", "name" => "a", "value" => 1}])

    assert {:error, :conflict_target_required} =
             DataIngestion.ingest(TestRepo, Widget, path)

    assert all_widgets() == []
  end