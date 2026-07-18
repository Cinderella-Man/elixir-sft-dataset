  defp factory(:user) do
    struct!(MyApp.User,
      name: sequence(:user_name, &"User #{&1}"),
      email: sequence(:user_email, &"user-#{&1}@example.com")
    )
  end

  defp factory(:post) do
    struct!(MyApp.Post,
      title: sequence(:post_title, &"Post title #{&1}"),
      body: sequence(:post_body, &"Post body #{&1}. Lorem ipsum dolor sit amet."),
      user_id: {:__assoc__, fn -> insert!(:user) end}
    )
  end

  defp factory(name) do
    raise ArgumentError, "No factory defined for #{inspect(name)}."
  end