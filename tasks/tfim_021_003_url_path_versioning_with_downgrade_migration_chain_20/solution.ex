  test "every supported version is renderable and no other version is accepted" do
    for version <- PathVersionApi.Migrations.supported() do
      assert call("/api/#{version}/users/1").status == 200
    end

    # Note: an empty version segment is not testable here — Plug collapses
    # "/api//users/1" to path_info ["api", "users", "1"], which is a different
    # route entirely rather than a request carrying an empty version.
    for version <- ["V1", "v0", "1", "v10", "v3.1", "v"] do
      refute version in PathVersionApi.Migrations.supported()
      assert call("/api/#{version}/users/1").status == 400
    end
  end