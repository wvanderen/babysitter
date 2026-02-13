defmodule Babysitter.TD.Handoff do
  @moduledoc """
  Schema for TD handoffs stored in SQLite.

  Handoffs capture the state of work when an agent pauses or stops,
  enabling context transfer to the next session.
  """
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "handoffs" do
    field(:issue_id, :string)
    field(:session_id, :string)
    field(:done, :string, default: "[]")
    field(:remaining, :string, default: "[]")
    field(:decisions, :string, default: "[]")
    field(:uncertain, :string, default: "[]")
    field(:timestamp, :naive_datetime)
  end

  @type t :: %__MODULE__{
          id: String.t(),
          issue_id: String.t(),
          session_id: String.t(),
          done: String.t(),
          remaining: String.t(),
          decisions: String.t(),
          uncertain: String.t(),
          timestamp: NaiveDateTime.t()
        }

  @doc """
  Parse the done field as a list.
  """
  @spec parse_done(t()) :: [String.t()]
  def parse_done(%__MODULE__{done: done}) when is_binary(done) do
    parse_json_list(done)
  end

  @doc """
  Parse the remaining field as a list.
  """
  @spec parse_remaining(t()) :: [String.t()]
  def parse_remaining(%__MODULE__{remaining: remaining}) when is_binary(remaining) do
    parse_json_list(remaining)
  end

  @doc """
  Parse the decisions field as a list.
  """
  @spec parse_decisions(t()) :: [String.t()]
  def parse_decisions(%__MODULE__{decisions: decisions}) when is_binary(decisions) do
    parse_json_list(decisions)
  end

  @doc """
  Parse the uncertain field as a list.
  """
  @spec parse_uncertain(t()) :: [String.t()]
  def parse_uncertain(%__MODULE__{uncertain: uncertain}) when is_binary(uncertain) do
    parse_json_list(uncertain)
  end

  defp parse_json_list(""), do: []
  defp parse_json_list(nil), do: []

  defp parse_json_list(json) do
    case Jason.decode(json) do
      {:ok, list} when is_list(list) -> list
      _ -> []
    end
  end
end
