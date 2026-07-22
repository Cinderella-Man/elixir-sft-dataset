defmodule InvertedIndexTest do
  use ExUnit.Case, async: false

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "iidx_#{System.pid()}_#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf(dir) end)
    %{dir: dir}
  end

  defp fresh_dir do
    Path.join(
      System.tmp_dir!(),
      "iidx_#{System.pid()}_#{System.unique_integer([:positive])}"
    )
  end

  # -------------------------------------------------------
  # Basic behaviour
  # -------------------------------------------------------

  test "indexes documents and finds them by keyword", %{dir: dir} do
    {:ok, pid} = InvertedIndex.start_link(dir: dir)
    :ok = InvertedIndex.index(pid, "doc1", %{body: "the quick brown fox"})
    :ok = InvertedIndex.index(pid, "doc2", %{body: "the quick brown cat"})

    results = InvertedIndex.search(pid, "fox")
    assert length(results) == 1
    assert hd(results).id == "doc1"
    :ok = GenServer.stop(pid)
  end

  test "stats reflects document and term counts", %{dir: dir} do
    {:ok, pid} = InvertedIndex.start_link(dir: dir)
    assert %{document_count: 0, term_count: 0} = InvertedIndex.stats(pid)

    :ok = InvertedIndex.index(pid, "doc1", %{body: "alpha beta gamma"})
    assert InvertedIndex.stats(pid).document_count == 1
    assert InvertedIndex.stats(pid).term_count == 3
    :ok = GenServer.stop(pid)
  end

  test "higher term frequency ranks first", %{dir: dir} do
    {:ok, pid} = InvertedIndex.start_link(dir: dir)
    :ok = InvertedIndex.index(pid, "doc1", %{body: "data data data analysis"})
    :ok = InvertedIndex.index(pid, "doc2", %{body: "data analysis report summary"})
    :ok = InvertedIndex.index(pid, "doc3", %{body: "report summary overview"})

    results = InvertedIndex.search(pid, "data")
    assert length(results) == 2
    assert hd(results).id == "doc1"
    assert hd(results).score > List.last(results).score
    :ok = GenServer.stop(pid)
  end

  test "stop words are not searchable", %{dir: dir} do
    {:ok, pid} = InvertedIndex.start_link(dir: dir)
    :ok = InvertedIndex.index(pid, "doc1", %{body: "the cat is on the mat"})
    assert InvertedIndex.search(pid, "the") == []
    assert length(InvertedIndex.search(pid, "cat")) == 1
    :ok = GenServer.stop(pid)
  end

  test "custom stop words override the defaults", %{dir: dir} do
    {:ok, pid} = InvertedIndex.start_link(dir: dir, stop_words: MapSet.new(["foo", "bar"]))
    :ok = InvertedIndex.index(pid, "doc1", %{body: "foo baz bar qux"})
    :ok = InvertedIndex.index(pid, "doc2", %{body: "the quick brown"})

    assert InvertedIndex.search(pid, "foo") == []
    assert length(InvertedIndex.search(pid, "the")) == 1
    :ok = GenServer.stop(pid)
  end

  test "limit caps the number of results", %{dir: dir} do
    {:ok, pid} = InvertedIndex.start_link(dir: dir)

    for i <- 1..20 do
      :ok = InvertedIndex.index(pid, "doc#{i}", %{body: "keyword variation#{i} text"})
    end

    assert length(InvertedIndex.search(pid, "keyword", limit: 5)) == 5
    assert length(InvertedIndex.search(pid, "keyword")) == 20
    :ok = GenServer.stop(pid)
  end

  test "removing non-existent doc does not raise", %{dir: dir} do
    {:ok, pid} = InvertedIndex.start_link(dir: dir)
    assert :ok = InvertedIndex.remove(pid, "nope")
    :ok = GenServer.stop(pid)
  end

  test "re-indexing replaces previous content", %{dir: dir} do
    {:ok, pid} = InvertedIndex.start_link(dir: dir)
    :ok = InvertedIndex.index(pid, "doc1", %{body: "apple banana"})
    assert length(InvertedIndex.search(pid, "apple")) == 1
    :ok = InvertedIndex.index(pid, "doc1", %{body: "cherry date"})
    assert InvertedIndex.search(pid, "apple") == []
    assert hd(InvertedIndex.search(pid, "cherry")).id == "doc1"
    assert InvertedIndex.stats(pid).document_count == 1
    :ok = GenServer.stop(pid)
  end

  test "suggest returns prefix matches sorted by document frequency", %{dir: dir} do
    {:ok, pid} = InvertedIndex.start_link(dir: dir)
    :ok = InvertedIndex.index(pid, "d1", %{body: "programming program problems"})
    :ok = InvertedIndex.index(pid, "d2", %{body: "program productivity projects"})
    :ok = InvertedIndex.index(pid, "d3", %{body: "testing productivity"})

    suggestions = InvertedIndex.suggest(pid, "pro")
    assert Enum.all?(suggestions, &String.starts_with?(&1, "pro"))
    top_two = Enum.take(suggestions, 2)
    assert "program" in top_two
    assert "productivity" in top_two
    assert length(InvertedIndex.suggest(pid, "pro", 2)) == 2
    assert InvertedIndex.suggest(pid, "xyz") == []
    :ok = GenServer.stop(pid)
  end

  test "search on empty index returns empty list", %{dir: dir} do
    {:ok, pid} = InvertedIndex.start_link(dir: dir)
    assert InvertedIndex.search(pid, "anything") == []
    :ok = GenServer.stop(pid)
  end

  # -------------------------------------------------------
  # Durability and recovery
  # -------------------------------------------------------

  test "index survives a graceful restart", %{dir: dir} do
    {:ok, pid} = InvertedIndex.start_link(dir: dir)
    :ok = InvertedIndex.index(pid, "d1", %{body: "alpha beta"})
    :ok = InvertedIndex.index(pid, "d2", %{body: "beta gamma"})
    :ok = GenServer.stop(pid)

    {:ok, pid2} = InvertedIndex.start_link(dir: dir)
    assert InvertedIndex.stats(pid2).document_count == 2
    assert [%{id: "d1"}] = InvertedIndex.search(pid2, "alpha")
    ids = InvertedIndex.search(pid2, "beta") |> Enum.map(& &1.id) |> Enum.sort()
    assert ids == ["d1", "d2"]
    :ok = GenServer.stop(pid2)
  end

  test "acknowledged writes survive a hard kill (no graceful shutdown)", %{dir: dir} do
    {:ok, pid} = InvertedIndex.start_link(dir: dir)
    :ok = InvertedIndex.index(pid, "d1", %{body: "alpha beta"})
    :ok = InvertedIndex.index(pid, "d2", %{body: "gamma delta"})

    # `start_link` links the server to this test process; unlink before the hard
    # kill so the untrappable `:killed` exit does not propagate and take the test
    # process down with it. This still exercises a crash with no graceful shutdown.
    ref = Process.monitor(pid)
    Process.unlink(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

    {:ok, pid2} = InvertedIndex.start_link(dir: dir)
    assert InvertedIndex.stats(pid2).document_count == 2
    assert [%{id: "d1"}] = InvertedIndex.search(pid2, "alpha")
    assert [%{id: "d2"}] = InvertedIndex.search(pid2, "gamma")
    :ok = GenServer.stop(pid2)
  end

  test "removal survives a restart", %{dir: dir} do
    {:ok, pid} = InvertedIndex.start_link(dir: dir)
    :ok = InvertedIndex.index(pid, "d1", %{body: "alpha beta"})
    :ok = InvertedIndex.index(pid, "d2", %{body: "gamma delta"})
    :ok = InvertedIndex.remove(pid, "d1")
    :ok = GenServer.stop(pid)

    {:ok, pid2} = InvertedIndex.start_link(dir: dir)
    assert InvertedIndex.stats(pid2).document_count == 1
    assert InvertedIndex.search(pid2, "alpha") == []
    assert [%{id: "d2"}] = InvertedIndex.search(pid2, "gamma")
    :ok = GenServer.stop(pid2)
  end

  test "snapshot compacts and state survives restart", %{dir: dir} do
    {:ok, pid} = InvertedIndex.start_link(dir: dir)
    :ok = InvertedIndex.index(pid, "d1", %{body: "alpha beta"})
    :ok = InvertedIndex.snapshot(pid)
    # a write after the snapshot lands only in the (truncated) WAL
    :ok = InvertedIndex.index(pid, "d2", %{body: "gamma delta"})
    :ok = GenServer.stop(pid)

    {:ok, pid2} = InvertedIndex.start_link(dir: dir)
    assert InvertedIndex.stats(pid2).document_count == 2
    assert [%{id: "d1"}] = InvertedIndex.search(pid2, "alpha")
    assert [%{id: "d2"}] = InvertedIndex.search(pid2, "gamma")
    :ok = GenServer.stop(pid2)
  end

  test "snapshot does not change query results", %{dir: dir} do
    {:ok, pid} = InvertedIndex.start_link(dir: dir)
    :ok = InvertedIndex.index(pid, "d1", %{body: "data data analysis"})
    :ok = InvertedIndex.index(pid, "d2", %{body: "data report"})

    before = InvertedIndex.search(pid, "data")
    :ok = InvertedIndex.snapshot(pid)
    after_snap = InvertedIndex.search(pid, "data")
    assert before == after_snap
    :ok = GenServer.stop(pid)
  end

  test "two directories are independent", %{dir: dir} do
    dir2 = fresh_dir()
    on_exit(fn -> File.rm_rf(dir2) end)

    {:ok, a} = InvertedIndex.start_link(dir: dir)
    {:ok, b} = InvertedIndex.start_link(dir: dir2)

    :ok = InvertedIndex.index(a, "d1", %{body: "alpha"})
    assert InvertedIndex.stats(b).document_count == 0
    assert InvertedIndex.search(b, "alpha") == []
    assert length(InvertedIndex.search(a, "alpha")) == 1

    :ok = GenServer.stop(a)
    :ok = GenServer.stop(b)
  end

  # -------------------------------------------------------
  # Misc
  # -------------------------------------------------------

  test "punctuation is stripped during tokenization", %{dir: dir} do
    {:ok, pid} = InvertedIndex.start_link(dir: dir)
    :ok = InvertedIndex.index(pid, "d1", %{body: "Hello, world! This is a test."})
    assert length(InvertedIndex.search(pid, "hello")) == 1
    assert length(InvertedIndex.search(pid, "world")) == 1
    :ok = GenServer.stop(pid)
  end

  test "accepts :name option for registration", %{dir: dir} do
    name = :"persistent_index_#{System.unique_integer([:positive])}"
    {:ok, _pid} = InvertedIndex.start_link(name: name, dir: dir)
    :ok = InvertedIndex.index(name, "d1", %{body: "hello world"})
    assert length(InvertedIndex.search(name, "hello")) == 1
    :ok = GenServer.stop(name)
  end
end
