defmodule Babysitter.Agent.Prompt do
  @moduledoc """
  Wraps agent prompts with completion marker instructions.

  This module injects instructions into agent prompts that tell the agent
  to output a specific completion marker when finished. This enables
  deterministic completion detection via the Babysitter.Agent.Completion module.

  ## Configuration

  Agents can be configured with:
    * `:completion_marker` - The marker to request (default: "BABYSITTER_DONE")
    * `:native_completion` - Set true for agents that have built-in completion

  ## Example

      iex> Babysitter.Agent.Prompt.wrap("Write a hello world")
      "Write a hello world\\n\\n---\\nWhen you have completed this task, output the following marker on its own line:\\nBABYSITTER_DONE\\n---"
  """

  alias Babysitter.Config

  @default_marker "BABYSITTER_DONE"

  @doc """
  Wrap a prompt with completion marker instructions.

  ## Options

    * `:marker` - Custom completion marker (default: "BABYSITTER_DONE")
    * `:enabled` - Whether to wrap the prompt (default: true)
    * `:instructions` - Custom instruction text (overrides default)

  ## Examples

      iex> Prompt.wrap("Write code")
      "Write code\\n\\n---\\nWhen you have completed this task..."

      iex> Prompt.wrap("Write code", enabled: false)
      "Write code"

      iex> Prompt.wrap("Write code", marker: "DONE")
      "Write code\\n\\n---\\nWhen you have completed this task...\\nDONE\\n---"
  """
  @spec wrap(String.t(), keyword()) :: String.t()
  def wrap(prompt, opts \\ [])

  def wrap(prompt, enabled: false), do: prompt

  def wrap(prompt, opts) when is_binary(prompt) do
    marker = Keyword.get(opts, :marker, @default_marker)
    custom_instructions = Keyword.get(opts, :instructions)

    instructions = custom_instructions || default_instructions(marker)

    """
    #{prompt}

    ---
    #{instructions}
    ---
    """
    |> String.trim_trailing()
  end

  @doc """
  Wrap a prompt for a specific agent using agent configuration.

  Checks the agent config for:
    * `:completion_marker` - Custom marker to use
    * `:native_completion` - If true, returns prompt unchanged

  ## Examples

      iex> Prompt.wrap_for_agent("Write code", :pi)
      "Write code\\n\\n---\\nWhen you have completed this task..."

      iex> Prompt.wrap_for_agent("Write code", :claude)
      "Write code"
  """
  @spec wrap_for_agent(String.t(), atom()) :: String.t()
  def wrap_for_agent(prompt, agent_name) when is_binary(prompt) and is_atom(agent_name) do
    if enabled_for_agent?(agent_name) do
      marker = get_agent_marker(agent_name)
      wrap(prompt, marker: marker)
    else
      prompt
    end
  end

  @doc """
  Check if prompt wrapping is enabled for an agent.

  Returns false if the agent has `:native_completion` set to true.

  ## Examples

      iex> Prompt.enabled_for_agent?(:pi)
      true

      iex> Prompt.enabled_for_agent?(:claude)
      false
  """
  @spec enabled_for_agent?(atom()) :: boolean()
  def enabled_for_agent?(agent_name) when is_atom(agent_name) do
    case Config.agent(agent_name) do
      nil -> true
      config -> not Map.get(config, :native_completion, false)
    end
  end

  @doc """
  Get the completion marker for an agent.

  ## Examples

      iex> Prompt.get_agent_marker(:pi)
      "BABYSITTER_DONE"

      iex> Prompt.get_agent_marker(:unknown)
      "BABYSITTER_DONE"
  """
  @spec get_agent_marker(atom()) :: String.t()
  def get_agent_marker(agent_name) when is_atom(agent_name) do
    case Config.agent(agent_name) do
      nil -> @default_marker
      config -> Map.get(config, :completion_marker, @default_marker)
    end
  end

  @doc """
  Generate default completion instructions for a marker.

  ## Examples

      iex> Prompt.default_instructions("DONE")
      "When you have completed this task, output the following marker on its own line:\\nDONE"
  """
  @spec default_instructions(String.t()) :: String.t()
  def default_instructions(marker) when is_binary(marker) do
    "When you have completed this task, output the following marker on its own line:\n#{marker}"
  end

  @doc """
  Get the default completion marker.

  ## Examples

      iex> Prompt.default_marker()
      "BABYSITTER_DONE"
  """
  @spec default_marker() :: String.t()
  def default_marker, do: @default_marker
end
