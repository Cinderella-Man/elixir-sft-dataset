  test "uses field_mapping to map CSV headers to schema fields" do
    header = ["Product ID", "Product Name", "Unit Price"]
    rows = [
      ["eid-1", "Widget A", "500"],
      ["eid-2", "Widget B", "600"]
    ]

    path = tmp_path("mapping.csv")
    write_csv!(path, header, rows)

    mapping = %{
      "Product ID"   => :external_id,
      "Product Name" => :name,
      "Unit Price"   => :price
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