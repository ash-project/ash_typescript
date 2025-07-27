defmodule AshTypescript.RpcV2.Context do
  @moduledoc """
  Context structure for field processing in the new RPC pipeline.
  
  Eliminates parameter threading by containing all necessary context
  for field parsing and processing operations.
  """

  @type t :: %__MODULE__{
    resource: module(),
    formatter: atom()
  }

  defstruct [:resource, :formatter]

  @doc """
  Creates a new context for field processing.
  """
  @spec new(module(), atom()) :: t()
  def new(resource, formatter) do
    %__MODULE__{
      resource: resource,
      formatter: formatter
    }
  end

  @doc """
  Creates a child context for nested resource processing.
  """
  @spec child(t(), module()) :: t()
  def child(%__MODULE__{formatter: formatter}, child_resource) do
    new(child_resource, formatter)
  end
end