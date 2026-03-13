defmodule AshApiSpec do
  @moduledoc """
  Generates a language-agnostic API specification from Ash resources and actions.

  Given a list of `{resource, action_name}` tuples or an OTP app, traverses the
  type graph to find all reachable resources and types, producing structured IR
  (Elixir structs) that can be serialized to JSON.
  """

  @type t :: %__MODULE__{
          version: String.t(),
          resources: [AshApiSpec.Resource.t()],
          types: [AshApiSpec.Type.t()]
        }

  defstruct version: "1.0.0",
            resources: [],
            types: []

  @doc """
  Generate an API specification for the given OTP app.

  ## Options

    * `:otp_app` - The OTP app to scan for Ash domains and resources (required)
    * `:actions` - Optional list of `{resource_module, action_name}` tuples to
      include. When omitted, all public actions across all domains are included.
  """
  @spec generate(keyword()) :: {:ok, t()} | {:error, term()}
  def generate(opts) do
    AshApiSpec.Generator.generate(opts)
  end
end
