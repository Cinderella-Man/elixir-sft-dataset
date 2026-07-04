  test "returns {:error, :invalid_json} for a malformed JSON file" do
    path = tmp_path("bad.json")
    File.write!(path, "{not json at all}")

    assert {:error, :invalid_json} =
             MultiSchemaIngestion.ingest(TestRepo, routing(), path)
  end