defmodule Trie do
  @type t :: %{
    children: %{char => t()} | nil,
    end_of_word: boolean()
  }

  @type word :: String.t()

  @doc """
  Creates a new, empty trie.
  """
  def new do
    %{children: nil, end_of_word: false}
  end

  @doc """
  Inserts a word into the trie and returns the new trie.
  If the word already exists, it returns the existing trie unchanged.
  """
  def insert(trie, word) when is_binary(word) do
    word
    |> String.graphemes()
    |> Enum.reduce(trie, fn
      char, %{children: children, end_of_word: true} ->
        # Word exists, return unchanged
        trie

      char, %{children: children, end_of_word: false} ->
        # Insert or update path
        build_node(trie, word, char)
    end)
  end

  defp build_node(trie, word, char) do
    %{trie |
      end_of_word: false,
      children: Map.put(trie.children, char, build_node(trie.children, word, char))
    }
  end

  @doc """
  Checks if the exact word exists in the trie.
  It does not return true if a prefix of the word exists.
  """
  def member?(trie, word) when is_binary(word) do
    word
    |> String.graphemes()
    |> Enum.reduce(trie, fn
      char, %{children: children} ->
        Map.get(children, char, nil)

      _, %{end_of_word: true} ->
        true

      _, _ ->
        false
    end)
  end

  @doc """
  Returns a sorted list of all words in the trie that start with the given prefix.
  Includes the prefix itself if it was inserted as a word.
  """
  def search(trie, prefix) when is_binary(prefix) do
    prefix
    |> String.graphemes()
    |> Enum.reduce({trie, []}, fn
      char, {node, acc} ->
        case Map.get(node.children, char) do
          child ->
            {child, Enum.concat(acc, [prefix <> char])}

          nil ->
            {node, acc}
        end

      _, {_, acc} ->
        # Check if current node marks the end of a word
        if Map.get(node, :end_of_word, false) do
          {node, [prefix | acc]}
        else
          {node, acc}
        end
    end)
    |> elem(1)
    |> Enum.sort()
  end

  @doc """
  Removes a word from the trie.
  Only removes the word if it exists; shared prefixes are preserved.
  Returns the updated trie.
  """
  def delete(trie, word) when is_binary(word) do
    word
    |> String.graphemes()
    |> Enum.reduce(trie, fn
      char, %{children: children, end_of_word: true} ->
        # Word exists
        new_children = delete_char(children, char)
        %{trie | children: new_children}

      char, %{children: children} ->
        # Path exists, but word doesn't end here
        new_children = delete_char(children, char)
        %{trie | children: new_children}

      _, _ ->
        # Word not found, return original trie
        trie
    end)
  end

  # Helper to remove a specific character key from children map
  # If the value becomes empty (nil children) and no end_of_word marker, it might be safe to remove the node
  defp delete_char(nil, _char), do: nil
  defp delete_char(%{}, _char), do: nil
  defp delete_char(children, char) when not is_binary(char) or is_atom(char), do: children

  defp delete_char(children, char) do
    children
    |> Map.delete(char)
    |> cond do
      %{children: _, end_of_word: false} = %{} ->
        # If map is empty and has no end_of_word, it's just a node on a path that no longer needs this child
        nil

      %{children: _, end_of_word: true} ->
        # If there's an end_of_word marker, we keep the map structure even if children are empty
        Map.delete(children, char)

      true ->
        # If it was the root or a specific case not covered above, just delete
        Map.delete(children, char)
    end
  end

  @doc """
  Returns the total count of words currently in the trie.
  """
  def size(trie) do
    count(trie, 0)
  end

  defp count(%{children: nil, end_of_word: false}, acc), do: acc
  defp count(%{children: children, end_of_word: true}, acc), do: acc + 1
  defp count(%{children: children}, acc), do: acc + Enum.reduce(children, 0, fn
    {_, node}, count -> count + count(node)
  end)

  @doc """
  Returns a sorted list of all words in the trie.
  """
  def words(trie) do
    words(trie, [])
  end

  defp words(%{children: nil, end_of_word: false}, acc), do: acc
  defp words(%{children: children, end_of_word: true}, acc), do: [prefix(trie, children, []) | Enum.concat(acc, words(children, acc))]
  defp words(%{children: children}, acc), do: Enum.concat(acc, words(children, acc))

  defp prefix(trie, children, acc) do
    children
    |> Map.keys()
    |> Enum.sort()
    |> Enum.flat_map(fn char ->
      {trie, char} |> build_path_prefix(acc) |> Enum.concat([prefix(trie, char.children, acc <> char)])
    end)
  end

  defp build_path_prefix({trie, char}, acc) do
    [{prefix_path, char_prefix} = {:prefix, char} | rest] =
      build_traversal(trie.children, acc <> char)
    prefix_path <> char_prefix
  end

  defp build_traversal(nil, acc), do: []
  defp build_traversal(%{}, acc), do: []

  defp build_traversal(children, acc) do
    children
    |> Map.keys()
    |> Enum.sort()
    |> Enum.flat_map(fn char ->
      build_traversal(Map.get(children, char, nil), acc <> char)
    end)
  end
end
