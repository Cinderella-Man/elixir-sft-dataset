    test "validates the name before the parent", %{server: s} do
      assert {:error, :invalid_name} = Archive.create_file(s, %{name: "", parent_id: 999})
    end