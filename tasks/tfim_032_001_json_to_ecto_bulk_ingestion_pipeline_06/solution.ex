  test "returns {:error, :invalid_json} for a malformed JSON file" do
    path = tmp_path("bad.json")
    File.write!(path, "{this is not json}")

    assert {:error, :invalid_json} =
             DataIngestion.ingest(TestRepo, Widget, path)
  end