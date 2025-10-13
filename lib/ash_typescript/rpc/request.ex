defmodule AshTypescript.Rpc.Request do
  @moduledoc """
  Request data structure for the new RPC pipeline.

  Contains all parsed and validated request data needed for Ash execution.
  Immutable structure that flows through the pipeline stages.
  """

  @type t :: %__MODULE__{
          resource: module(),
          action: map(),
          rpc_action: map(),
          tenant: term(),
          actor: term(),
          context: map(),
          select: list(atom()),
          load: list(),
          extraction_template: map(),
          input: map(),
          primary_key: term(),
          filter: map() | nil,
          sort: list() | nil,
          pagination: map() | nil,
          show_metadata: list(atom())
        }

  defstruct [
    :resource,
    :action,
    :rpc_action,
    :tenant,
    :actor,
    :context,
    :select,
    :load,
    :extraction_template,
    :input,
    :primary_key,
    :filter,
    :sort,
    :pagination,
    show_metadata: []
  ]

  @doc """
  Creates a new Request with validated parameters.
  """
  @spec new(map()) :: t()
  def new(params) when is_map(params) do
    struct(__MODULE__, params)
  end
end
