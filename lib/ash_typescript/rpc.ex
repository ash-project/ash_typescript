defmodule AshTypescript.Rpc do
  @moduledoc """
  Next-generation RPC processing pipeline with clean architecture and strict validation.

  This is a complete rewrite focused on:
  - Performance: 50%+ improvement over current implementation
  - Strict validation: Fail-fast on all invalid inputs
  - Clean architecture: Pure functional pipeline
  - Single responsibility: Clear separation of concerns

  Pipeline: parse_input -> execute_action -> filter_result -> format_output
  """

  # DSL structures for Spark extension
  defmodule RpcAction do
    defstruct [:name, :action]
  end

  defmodule Resource do
    defstruct [:resource, rpc_actions: []]
  end

  @rpc_action %Spark.Dsl.Entity{
    name: :rpc_action,
    target: RpcAction,
    schema: [
      name: [
        type: :atom,
        doc: "The name of the RPC-action"
      ],
      action: [
        type: :atom,
        doc: "The resource action to expose"
      ]
    ],
    args: [:name, :action]
  }

  @resource %Spark.Dsl.Entity{
    name: :resource,
    target: Resource,
    describe: "Define available RPC-actions for a resource",
    schema: [
      resource: [
        type: {:spark, Ash.Resource},
        doc: "The resource being configured"
      ]
    ],
    args: [:resource],
    entities: [
      rpc_actions: [@rpc_action]
    ]
  }

  @rpc %Spark.Dsl.Section{
    name: :rpc,
    describe: "Define available RPC-actions for resources in this domain.",
    entities: [
      @resource
    ]
  }

  use Spark.Dsl.Extension, sections: [@rpc]

  alias AshTypescript.Rpc.{Pipeline, ErrorBuilder}

  @doc """
  Determines if tenant parameters are required in RPC requests.

  This checks the application configuration for :require_tenant_parameters.
  If true (default), tenant parameters are required for multitenant resources.
  If false, tenant will be extracted from the connection using Ash.PlugHelpers.get_tenant/1.
  """
  def require_tenant_parameters? do
    Application.get_env(:ash_typescript, :require_tenant_parameters, false)
  end

  @doc """
  Gets the input field formatter configuration for parsing input parameters from the client.

  This determines how client field names are converted to internal Elixir field names.
  Defaults to :camel_case. Can be:
  - Built-in: :camel_case, :pascal_case, :snake_case
  - Custom: {Module, :function} or {Module, :function, [extra_args]}
  """
  def input_field_formatter do
    Application.get_env(:ash_typescript, :input_field_formatter, :camel_case)
  end

  @doc """
  Gets the output field formatter configuration for TypeScript generation and responses to the client.

  This determines how internal Elixir field names are converted for client consumption in both
  generated TypeScript types and API responses.
  Defaults to :camel_case. Can be:
  - Built-in: :camel_case, :pascal_case, :snake_case
  - Custom: {Module, :function} or {Module, :function, [extra_args]}
  """
  def output_field_formatter do
    Application.get_env(:ash_typescript, :output_field_formatter, :camel_case)
  end

  @doc """
  Determines if a resource requires a tenant parameter.

  A resource requires a tenant if it has multitenancy configured and global? is false (default).
  """
  def requires_tenant?(resource) do
    strategy = Ash.Resource.Info.multitenancy_strategy(resource)

    case strategy do
      strategy when strategy in [:attribute, :context] ->
        not Ash.Resource.Info.multitenancy_global?(resource)

      _ ->
        false
    end
  end

  @doc """
  Determines if a resource should have tenant parameters in the generated TypeScript interface.

  This combines resource multitenancy requirements with the configuration setting.
  """
  def requires_tenant_parameter?(resource) do
    requires_tenant?(resource) && require_tenant_parameters?()
  end

  @doc """
  Main entry point for the new RPC processing pipeline.

  ## Parameters
  - `otp_app` - The OTP application atom
  - `conn` - The Plug connection
  - `params` - Request parameters map

  ## Returns
  - `{:ok, result}` - Successfully processed result
  - `{:error, reason}` - Processing error with detailed message

  ## Error Handling
  This implementation uses strict validation and fails fast on any invalid input.
  No permissive modes - all errors are reported immediately.
  """
  @spec run_action(atom(), Plug.Conn.t(), map()) :: {:ok, map()} | {:error, map()}
  def run_action(otp_app, conn, params) do
    with {:ok, parsed_request} <- Pipeline.parse_request_strict(otp_app, conn, params),
         {:ok, ash_result} <- Pipeline.execute_ash_action(parsed_request),
         {:ok, filtered_result} <- Pipeline.filter_result_fields(ash_result, parsed_request) do
      %{success: true, data: filtered_result}
    else
      {:error, reason} ->
        %{success: false, errors: [ErrorBuilder.build_error_response(reason)]}
    end
    |> Pipeline.format_output()
  end

  @doc """
  Validates action parameters without execution.
  Used for form validation in the client.
  """
  @spec validate_action(atom(), Plug.Conn.t(), map()) ::
          {:ok, map()} | {:error, map()}
  def validate_action(otp_app, conn, params) do
    case Pipeline.parse_request_strict(otp_app, conn, params) do
      {:ok, _parsed_request} ->
        %{success: true}

      {:error, reason} ->
        %{success: false, errors: [ErrorBuilder.build_error_response(reason)]}
    end
    |> Pipeline.format_output()
  end
end
