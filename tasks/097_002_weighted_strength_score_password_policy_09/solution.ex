  defp similarity_reason(password, %{username: username, max_username_similarity: threshold}) do
    dist = levenshtein(String.downcase(password), String.downcase(username))
    if dist <= threshold, do: :too_similar_to_username, else: nil
  end