defmodule Babysitter.Config do
  @moduledoc """
  Configuration module for Babysitter daemon.

  Reads from ~/.config/babysitter/config.yaml with sensible defaults.
  Supports environment variable interpolation via ${VAR_NAME} syntax.
  """

  @default_config %{
    daemon: %{
      port: 4001,
      log_level: "info"
    },
    tmux: %{
      base_session: "babysitter"
    },
    td: %{
      database: ".todos/issues.db"
    },
    agents: %{
      claude: %{
        command: "claude",
        args: ["--dangerously-skip-permissions"]
      },
      opencode: %{
        command: "opencode",
        args: []
      },
      pi: %{
        command: "pi",
        args: ["--no-session"]
      }
    },
    git: %{
      commit_strategy: %{
        trigger: "stage_complete",
        message_template: "{{issue.id}}: {{issue.title}}\n\n{{stage.summary}}"
      },
      pr_strategy: %{
        trigger: "manual"
      },
      normalization: %{
        patterns: ["wip:", "fixup:", "tmp:", "draft:"],
        time_window_minutes: 60
      }
    },
    intervention: %{
      default_intelligence: "hybrid",
      max_retries: 3,
      timeout_minutes: 30,
      stuck_threshold_minutes: 10
    },
    providers: %{},
    concurrency: %{
      max_parallel_sessions: 3
    }
  }

  @config_dir "~/.config/babysitter"
  @config_file "config.yaml"

  @doc """
  Get the full configuration, merged with defaults.
  """
  @spec all() :: map()
  def all do
    default = @default_config
    user = load_user_config()
    deep_merge(default, user)
  end

  @doc """
  Get a specific config value by path.

  ## Examples

      iex> Babysitter.Config.get(:daemon, :port)
      4001
      
      iex> Babysitter.Config.get(:agents, :claude, :command)
      "claude"
  """
  def get(key), do: all()[key]
  def get(key1, key2), do: get_in(all(), [key1, key2])
  def get(key1, key2, key3), do: get_in(all(), [key1, key2, key3])
  def get(key1, key2, key3, key4), do: get_in(all(), [key1, key2, key3, key4])

  @doc """
  Get daemon configuration.
  """
  @spec daemon() :: map()
  def daemon, do: get(:daemon) || @default_config.daemon

  @doc """
  Get tmux configuration.
  """
  @spec tmux() :: map()
  def tmux, do: get(:tmux) || @default_config.tmux

  @doc """
  Get td configuration.
  """
  @spec td() :: map()
  def td, do: get(:td) || @default_config.td

  @doc """
  Get agent configuration by name.
  """
  @spec agent(atom()) :: map() | nil
  def agent(name) when is_atom(name) do
    get(:agents, name)
  end

  @doc """
  Get all configured agents.
  """
  @spec agents() :: map()
  def agents, do: get(:agents) || @default_config.agents

  @doc """
  Get git configuration.
  """
  @spec git() :: map()
  def git, do: get(:git) || @default_config.git

  @doc """
  Get git normalization configuration.
  """
  @spec git_normalization() :: map()
  def git_normalization, do: get(:git, :normalization) || @default_config.git.normalization

  @doc """
  Get intervention configuration.
  """
  @spec intervention() :: map()
  def intervention, do: get(:intervention) || @default_config.intervention

  @doc """
  Get provider configuration.
  """
  @spec providers() :: map()
  def providers, do: get(:providers) || %{}

  @doc """
  Get concurrency configuration.
  """
  @spec concurrency() :: map()
  def concurrency, do: get(:concurrency) || @default_config.concurrency

  @doc """
  Get the path to the config file.
  """
  @spec config_path() :: String.t()
  def config_path do
    Path.join([Path.expand(@config_dir), @config_file])
  end

  @doc """
  Check if config file exists.
  """
  @spec config_exists?() :: boolean()
  def config_exists? do
    File.exists?(config_path())
  end

  @doc """
  Ensure config directory exists.
  """
  @spec ensure_config_dir!() :: :ok | {:error, term()}
  def ensure_config_dir! do
    dir = Path.expand(@config_dir)

    if File.dir?(dir) do
      :ok
    else
      case File.mkdir_p(dir) do
        :ok -> :ok
        error -> error
      end
    end
  end

  @doc """
  Write a sample configuration file.
  """
  @spec write_sample_config!() :: :ok | {:error, term()}
  def write_sample_config! do
    ensure_config_dir!()

    sample = """
    # Babysitter Configuration
    # See: https://github.com/your-org/babysitter#configuration

    daemon:
      port: 4001
      log_level: info

    tmux:
      base_session: babysitter

    td:
      database: .todos/issues.db

    agents:
      claude:
        command: claude
        args:
          - --dangerously-skip-permissions
      opencode:
        command: opencode
        args: []
      pi:
        command: pi
        args:
          - --no-session

    git:
      commit_strategy:
        trigger: stage_complete
        message_template: |
          {{issue.id}}: {{issue.title}}

          {{stage.summary}}
      pr_strategy:
        trigger: manual
      normalization:
        patterns:
          - "wip:"
          - "fixup:"
          - "tmp:"
          - "draft:"
        time_window_minutes: 60

    intervention:
      default_intelligence: hybrid
      max_retries: 3
      timeout_minutes: 30
      stuck_threshold_minutes: 10

    # Uncomment to configure API providers
    # providers:
    #   anthropic:
    #     api_key: "${ANTHROPIC_API_KEY}"
    #     default_model: "claude-sonnet-4-20250514"
    #   openai:
    #     api_key: "${OPENAI_API_KEY}"
    #     default_model: "gpt-4.1"

    concurrency:
      max_parallel_sessions: 3
    """

    path = config_path()

    if File.exists?(path) do
      {:error, :already_exists}
    else
      case File.write(path, sample) do
        :ok ->
          IO.puts("Created sample config at #{path}")
          :ok

        error ->
          error
      end
    end
  end

  defp load_user_config do
    path = config_path()

    if File.exists?(path) do
      case :yamerl.decode_file(String.to_charlist(path)) do
        [config | _] when is_list(config) ->
          config
          |> atomize_keys()
          |> interpolate_env_vars()

        _ ->
          %{}
      end
    else
      %{}
    end
  rescue
    _ -> %{}
  end

  defp atomize_keys(config) when is_list(config) do
    config
    |> Enum.map(fn {k, v} ->
      key = if is_list(k), do: List.to_atom(k), else: k
      {key, atomize_keys(v)}
    end)
    |> Map.new()
  end

  defp atomize_keys(config) when is_map(config) do
    Map.new(config, fn {k, v} -> {k, atomize_keys(v)} end)
  end

  defp atomize_keys(config) when is_list(config) and not is_tuple(hd(config)) do
    Enum.map(config, &atomize_keys/1)
  end

  defp atomize_keys(other), do: other

  defp interpolate_env_vars(config) when is_map(config) do
    Map.new(config, fn {k, v} -> {k, interpolate_env_vars(v)} end)
  end

  defp interpolate_env_vars(config) when is_list(config) do
    Enum.map(config, &interpolate_env_vars/1)
  end

  defp interpolate_env_vars(value) when is_binary(value) do
    Regex.replace(~r/\$\{([A-Za-z_][A-Za-z0-9_]*)\}/, value, fn _, var_name ->
      System.get_env(var_name) || ""
    end)
  end

  defp interpolate_env_vars(other), do: other

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn
      _key, left_val, right_val when is_map(left_val) and is_map(right_val) ->
        deep_merge(left_val, right_val)

      _key, _left_val, right_val ->
        right_val
    end)
  end

  defp deep_merge(_left, right), do: right
end
