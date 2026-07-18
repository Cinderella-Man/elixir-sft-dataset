  test "supported/0 lists versions ascending" do
    assert PathVersionApi.Migrations.supported() == ["v1", "v2", "v3"]
  end