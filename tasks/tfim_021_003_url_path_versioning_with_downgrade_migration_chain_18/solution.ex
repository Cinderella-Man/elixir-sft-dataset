  test "render/3 for v2 applies exactly the one downgrade step" do
    user = %{
      first_name: "Zoe",
      last_name: "Lin",
      email: "zoe@example.com",
      created_at: "2023-03-03T00:00:00Z",
      country: "SG"
    }

    assert PathVersionApi.Migrations.render("v2", "42", user) ==
             %{
               id: "42",
               first_name: "Zoe",
               last_name: "Lin",
               email: "zoe@example.com",
               created_at: "2023-03-03T00:00:00Z"
             }
  end