# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Request do
  @moduledoc """
  Request data structure for the new RPC pipeline.

  Contains all parsed and validated request data needed for Ash execution.
  Immutable structure that flows through the pipeline stages.
  """

  @type t :: %__MODULE__{
          domain: module(),
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
          identity: term(),
          get_by: map() | nil,
          filter: map() | nil,
          sort: list() | nil,
          pagination: map() | nil,
          show_metadata: list(atom())
        }

  defstruct [
    :domain,
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
    :identity,
    :get_by,
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
