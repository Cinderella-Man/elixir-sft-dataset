  defp canonical(user, id) do
    %{
      id: id,
      name: %{first: user.first_name, last: user.last_name},
      email: user.email,
      created_at: user.created_at,
      country: user.country
    }
  end