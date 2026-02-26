defmodule Babysitter.Tmux.VerifierTest do
  use ExUnit.Case, async: true

  alias Babysitter.Tmux.Verifier

  describe "verify_tmux_available/0" do
    test "returns ok with version when tmux is installed" do
      assert {:ok, version} = Verifier.verify_tmux_available()
      assert is_binary(version)
      assert String.match?(version, ~r/^\d+\.\d+/)
    end

    test "returns error when command does not exist" do
      original_path = System.get_env("PATH")

      System.put_env("PATH", "/nonexistent")
      on_exit(fn -> System.put_env("PATH", original_path) end)

      assert {:error, :tmux_not_found} = Verifier.verify_tmux_available()
    end
  end

  describe "verify_tmux_available!/0" do
    test "returns version when tmux is installed" do
      assert version = Verifier.verify_tmux_available!()
      assert is_binary(version)
    end

    test "raises when tmux is not installed" do
      original_path = System.get_env("PATH")

      System.put_env("PATH", "/nonexistent")
      on_exit(fn -> System.put_env("PATH", original_path) end)

      assert_raise RuntimeError, ~r/tmux is not installed/, fn ->
        Verifier.verify_tmux_available!()
      end
    end
  end

  describe "parse_version/1" do
    test "extracts version from standard tmux output" do
      assert "3.4" = Verifier.parse_version("tmux 3.4")
    end

    test "handles leading/trailing whitespace" do
      assert "3.4" = Verifier.parse_version("  tmux 3.4  ")
      assert "3.4" = Verifier.parse_version("\ttmux 3.4\n")
    end

    test "handles case-insensitive tmux prefix" do
      assert "3.4" = Verifier.parse_version("TMUX 3.4")
      assert "3.4" = Verifier.parse_version("Tmux 3.4")
    end

    test "handles unusual version formats" do
      assert "next-3.4" = Verifier.parse_version("tmux next-3.4")
      assert "3.4-rc" = Verifier.parse_version("tmux 3.4-rc")
      assert "3.4.1" = Verifier.parse_version("tmux 3.4.1")
    end

    test "handles empty string gracefully" do
      assert "" = Verifier.parse_version("")
    end

    test "handles output without version number" do
      assert "random text" = Verifier.parse_version("random text")
      assert "error message" = Verifier.parse_version("error message")
    end

    test "handles version at different positions" do
      assert "3.4 extra" = Verifier.parse_version("tmux 3.4 extra")
    end
  end

  describe "installation_instructions/0" do
    test "returns installation instructions" do
      instructions = Verifier.installation_instructions()

      assert instructions =~ "macOS"
      assert instructions =~ "Ubuntu"
      assert instructions =~ "brew install tmux"
      assert instructions =~ "apt-get install tmux"
    end
  end
end
