defmodule Babysitter.Intervention do
  @moduledoc """
  Intervention engine for handling stuck or failed sessions.

  Two modes:
  - `:dumb` - Rules-based intervention (max retries, timeout, validation failure)
  - `:smart` - LLM-powered analysis (future)
  - `:hybrid` - Dumb for happy path, smart on failure
  """

  defmodule Result do
    @moduledoc """
    Result of an intervention check.
    """

    @type action :: :ok | :retry | :restart | :escalate | :skip

    @type t :: %__MODULE__{
            action: action(),
            reason: String.t() | nil,
            context: map() | nil,
            stage_id: String.t() | nil
          }

    @enforce_keys [:action]
    defstruct [:action, :reason, :context, :stage_id]

    @spec ok() :: t()
    def ok, do: %__MODULE__{action: :ok}

    @spec retry(String.t(), keyword()) :: t()
    def retry(reason, opts \\ []) do
      %__MODULE__{
        action: :retry,
        reason: reason,
        context: Keyword.get(opts, :context),
        stage_id: Keyword.get(opts, :stage_id)
      }
    end

    @spec restart(String.t(), keyword()) :: t()
    def restart(reason, opts \\ []) do
      %__MODULE__{
        action: :restart,
        reason: reason,
        context: Keyword.get(opts, :context),
        stage_id: Keyword.get(opts, :stage_id)
      }
    end

    @spec escalate(String.t(), keyword()) :: t()
    def escalate(reason, opts \\ []) do
      %__MODULE__{
        action: :escalate,
        reason: reason,
        context: Keyword.get(opts, :context),
        stage_id: Keyword.get(opts, :stage_id)
      }
    end

    @spec skip(String.t(), keyword()) :: t()
    def skip(reason, opts \\ []) do
      %__MODULE__{
        action: :skip,
        reason: reason,
        context: Keyword.get(opts, :context),
        stage_id: Keyword.get(opts, :stage_id)
      }
    end

    @spec needs_action?(t()) :: boolean()
    def needs_action?(%__MODULE__{action: :ok}), do: false
    def needs_action?(%__MODULE__{}), do: true
  end

  alias Babysitter.Intervention.Dumb
  alias Babysitter.Intervention.Result

  @doc """
  Check if intervention is needed for a session.

  Uses the intelligence mode to determine which checker to use.
  """
  @spec check(map(), atom()) :: Result.t()
  def check(session, intelligence \\ :dumb) do
    case intelligence do
      :dumb -> Dumb.check(session)
      :smart -> check_smart(session)
      :hybrid -> check_hybrid(session)
    end
  end

  defp check_smart(_session) do
    raise "Smart intervention not yet implemented"
  end

  defp check_hybrid(session) do
    case Dumb.check(session) do
      %Result{action: :ok} = result ->
        result

      %Result{action: :escalate} = result ->
        result

      %Result{} = result ->
        if should_use_smart?(session) do
          check_smart(session)
        else
          result
        end
    end
  end

  defp should_use_smart?(session) do
    retry_count = get_retry_count(session)
    retry_count >= 2
  end

  defp get_retry_count(session) do
    case Map.get(session, :retries) do
      nil ->
        0

      retries when is_map(retries) ->
        stage_id = Map.get(session, :current_stage)
        Map.get(retries, stage_id, 0)

      _ ->
        0
    end
  end
end
