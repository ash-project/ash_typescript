defmodule AshTypescript.Rpc.FieldParser.Context do
  @moduledoc """
  Context struct for field parsing operations.

  Encapsulates common parameters passed throughout the field parsing pipeline
  to reduce parameter passing and improve readability.
  """

  defstruct [:resource, :formatter, :parent_resource]

  @type t :: %__MODULE__{
          resource: module(),
          formatter: atom(),
          parent_resource: module() | nil
        }

  @doc """
  Create a new parsing context.

  ## Parameters
  - resource: The Ash resource module being parsed
  - formatter: The field formatter to use (e.g., :camel_case)
  - parent_resource: Optional parent resource for nested contexts
  """
  @spec new(module(), atom(), module() | nil) :: t()
  def new(resource, formatter, parent_resource \\ nil) do
    %__MODULE__{
      resource: resource,
      formatter: formatter,
      parent_resource: parent_resource
    }
  end

  @doc """
  Create a child context for processing nested fields (relationships, embedded resources).

  Preserves the formatter while updating the resource context.
  """
  @spec child(t(), module()) :: t()
  def child(%__MODULE__{} = context, new_resource) do
    %__MODULE__{
      resource: new_resource,
      formatter: context.formatter,
      parent_resource: context.resource
    }
  end
end
