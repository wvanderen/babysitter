defmodule Babysitter.SetupTest do
  use ExUnit.Case, async: true

  alias Babysitter.Setup

  describe "required_dirs/0" do
    test "returns list of required directories" do
      dirs = Setup.required_dirs()

      assert is_list(dirs)
      assert "data/babysitter" in dirs
      assert "data/langgraph" in dirs
      assert ".babysitter/workflows" in dirs
    end
  end

  describe "ensure_directories/0" do
    test "creates all required directories if missing" do
      test_id = :rand.uniform(1_000_000)
      test_base = "test_tmp_#{test_id}"

      dirs = [
        "#{test_base}/data/babysitter",
        "#{test_base}/data/langgraph",
        "#{test_base}/.babysitter/workflows"
      ]

      on_exit(fn ->
        File.rm_rf!(test_base)
      end)

      Enum.each(dirs, fn dir ->
        refute File.dir?(dir), "Directory #{dir} should not exist before test"
      end)

      :ok = Setup.ensure_directories(dirs)

      Enum.each(dirs, fn dir ->
        assert File.dir?(dir), "Directory #{dir} should exist after ensure_directories"
      end)
    end

    test "returns :ok when directories already exist" do
      test_id = :rand.uniform(1_000_000)
      test_base = "test_tmp_#{test_id}"

      dirs = [
        "#{test_base}/data/babysitter",
        "#{test_base}/data/langgraph",
        "#{test_base}/.babysitter/workflows"
      ]

      on_exit(fn ->
        File.rm_rf!(test_base)
      end)

      Enum.each(dirs, &File.mkdir_p/1)

      assert :ok = Setup.ensure_directories(dirs)
    end
  end

  describe "ensure_directories!/0" do
    test "creates default required directories" do
      test_id = :rand.uniform(1_000_000)
      test_base = "test_tmp_#{test_id}"

      original_cwd = File.cwd!()
      test_dir = Path.join(original_cwd, test_base)
      File.mkdir_p!(test_dir)
      File.cd!(test_dir)

      on_exit(fn ->
        File.cd!(original_cwd)
        File.rm_rf!(test_base)
      end)

      assert :ok = Setup.ensure_directories!()

      assert File.dir?("data/babysitter")
      assert File.dir?("data/langgraph")
      assert File.dir?(".babysitter/workflows")
    end
  end
end
