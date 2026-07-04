  test "returns {:error, :not_a_list} when the JSON root is not an array" do
    path = tmp_path("object.json")
    write_json!(path, %{"key" => "value"})

    assert {:error, :not_a_list} =
             DataIngestion.ingest(TestRepo, Widget, path)
  end