    test "rejects invalid names", %{server: s} do
      assert {:error, :invalid_name} = Archive.create_folder(s, %{})
      assert {:error, :invalid_name} = Archive.create_folder(s, %{name: ""})
      assert {:error, :invalid_name} = Archive.create_folder(s, %{name: "   "})
      assert {:error, :invalid_name} = Archive.create_folder(s, %{name: :nope})
    end