  test "render/3 for v3 returns the canonical document verbatim with no steps applied" do
    user = %{
      first_name: "Zoe",
      last_name: "Lin",
      email: "zoe@example.com",
      created_at: "2023-03-03T00:00:00Z",
      country: "SG"
    }

    assert PathVersionApi.Migrations.render("v3", "42", user) ==
             %{
               id: "42",
               name: %{first: "Zoe", last: "Lin"},
               email: "zoe@example.com",
               created_at: "2023-03-03T00:00:00Z",
               country: "SG"
             }
  end