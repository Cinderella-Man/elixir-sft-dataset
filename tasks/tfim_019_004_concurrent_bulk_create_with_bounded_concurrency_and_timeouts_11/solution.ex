  test "store stays consistent for later batches after a timed-out item is killed" do
    first =
      ConcurrentCatalog.bulk_create(
        [
          %{"name" => "gone", "price" => 5, "delay" => 600},
          %{"name" => "kept", "price" => 6}
        ],
        max_concurrency: 2,
        timeout_ms: 150
      )

    assert {0, :error, :timeout} = Enum.at(first, 0)
    assert {1, :ok, _} = Enum.at(first, 1)

    second =
      ConcurrentCatalog.bulk_create([
        %{"name" => "after1", "price" => 7},
        %{"name" => "after2", "price" => 8}
      ])

    assert Enum.all?(second, fn {_i, tag, _reason} -> tag == :ok end)
    assert ConcurrentCatalog.count() == 3

    # Every reported item is retrievable by its own id, across both batches.
    for {_i, :ok, item} <- first ++ second do
      assert ConcurrentCatalog.get(item.id) == item
    end

    assert Enum.sort(Enum.map(ConcurrentCatalog.all(), & &1.name)) ==
             ["after1", "after2", "kept"]

    assert ConcurrentCatalog.get(999_999) == nil
  end