  defp required(:user), do: [:name, :email]
  defp required(:post), do: [:title, :body, :user_id]