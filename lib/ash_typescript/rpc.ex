# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc do
  @moduledoc false

  defmodule RpcAction do
    @moduledoc """
    Struct representing an RPC action configuration.

    Defines the mapping between a named RPC endpoint and an Ash action.
    """
    defstruct [:name, :action, :show_metadata, :metadata_field_names, __spark_metadata__: nil]
  end

  defmodule Resource do
    @moduledoc """
    Struct representing a resource's RPC configuration.

    Contains the resource module and lists of configured RPC actions
    and typed queries for that resource.
    """
    defstruct [:resource, rpc_actions: [], typed_queries: [], __spark_metadata__: nil]
  end

  defmodule TypedQuery do
    @moduledoc """
    Struct representing a typed query configuration.

    Defines a pre-configured query with specific fields and TypeScript types,
    allowing for type-safe, reusable query patterns in the generated RPC client.
    """
    defstruct [
      :name,
      :ts_result_type_name,
      :ts_fields_const_name,
      :resource,
      :action,
      :fields,
      __spark_metadata__: nil
    ]
  end

  @typed_query %Spark.Dsl.Entity{
    name: :typed_query,
    target: TypedQuery,
    schema: [
      action: [
        type: :atom,
        doc: "The read action on the resource to query"
      ],
      name: [
        type: :atom,
        doc: "The name of the RPC-action"
      ],
      ts_result_type_name: [
        type: :string,
        doc: "The name of the TypeScript type for the query result"
      ],
      ts_fields_const_name: [
        type: :string,
        doc:
          "The name of the constant for the fields, that can be reused by the client to re-run the query"
      ],
      fields: [
        type: {:list, :any},
        doc: "The fields to query"
      ]
    ],
    args: [:name, :action]
  }

  @rpc_action %Spark.Dsl.Entity{
    name: :rpc_action,
    target: RpcAction,
    describe: """
    Define an RPC action that exposes a resource action to TypeScript clients.

    Metadata fields: Action metadata can be exposed via `show_metadata` option.
    Set to `nil` (default) to expose all metadata fields, `false` or `[]` to disable,
    or provide a list of atoms to expose specific fields.

    Metadata field naming: Use `metadata_field_names` to map invalid metadata field names
    (e.g., `field_1`, `is_valid?`) to valid TypeScript identifiers.
    Example: `metadata_field_names [field_1: :field1, is_valid?: :isValid]`
    """,
    schema: [
      name: [
        type: :atom,
        doc: "The name of the RPC-action"
      ],
      action: [
        type: :atom,
        doc: "The resource action to expose"
      ],
      show_metadata: [
        type: {:or, [nil, :boolean, {:list, :atom}]},
        doc: "Which metadata fields to expose (nil=all, false/[]=none, list=specific fields)",
        default: nil
      ],
      metadata_field_names: [
        type: {:list, {:tuple, [:atom, :atom]}},
        doc: "Map metadata field names to valid TypeScript identifiers",
        default: []
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
      rpc_actions: [@rpc_action],
      typed_queries: [@typed_query]
    ]
  }

  @rpc %Spark.Dsl.Section{
    name: :typescript_rpc,
    describe: "Define available RPC-actions for resources in this domain.",
    schema: [
      error_handler: [
        type: {:or, [:mfa, :module]},
        doc: """
        An MFA or module that implements error handling for RPC operations.

        The error handler will be called with (error, context) and should return a modified error map.
        If a module is provided, it must export a handle_error/2 function.

        Example:
        ```elixir
        error_handler {MyApp.CustomErrorHandler, :handle_error, []}
        # or
        error_handler MyApp.CustomErrorHandler
        ```
        """,
        default: {AshTypescript.Rpc.DefaultErrorHandler, :handle_error, []}
      ],
      show_raised_errors?: [
        type: :boolean,
        default: false,
        doc: """
        Whether to show detailed information for raised exceptions.

        Set to true in development to see full error details.
        Keep false in production for security.
        """
      ]
    ],
    entities: [
      @resource
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@rpc],
    verifiers: [
      AshTypescript.Rpc.VerifyRpc,
      AshTypescript.Rpc.Verifiers.VerifyMetadataFieldNames,
      AshTypescript.Rpc.Verifiers.VerifyTypedQueryFields,
      AshTypescript.Rpc.VerifyRpcWarnings
    ]

  alias AshTypescript.Rpc.{ErrorBuilder, Pipeline}

  def codegen(args) do
    Mix.Task.reenable("ash_typescript.codegen")
    Mix.Task.run("ash_typescript.codegen", args)
  end

  @doc """
  Determines if tenant parameters are required in RPC requests.

  This checks the application configuration for :require_tenant_parameters.
  If true (default), tenant parameters are required for multitenant resources.
  If false, tenant will be extracted from the connection using Ash.PlugHelpers.get_tenant/1.
  """
  def require_tenant_parameters? do
    Application.get_env(:ash_typescript, :require_tenant_parameters)
  end

  @doc """
  Gets the input field formatter configuration for parsing input parameters from the client.

  This determines how client field names are converted to internal Elixir field names.
  Defaults to :camel_case. Can be:
  - Built-in: :camel_case, :pascal_case, :snake_case
  - Custom: {Module, :function} or {Module, :function, [extra_args]}
  """
  def input_field_formatter do
    Application.get_env(:ash_typescript, :input_field_formatter)
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
    Application.get_env(:ash_typescript, :output_field_formatter)
  end

  @doc """
  Determines if Zod schema generation is enabled.

  When true, generates Zod schemas alongside TypeScript types for runtime validation.
  Defaults to false (opt-in feature).
  """
  def generate_zod_schemas? do
    Application.get_env(:ash_typescript, :generate_zod_schemas)
  end

  @doc """
  Gets the Zod import path for generated TypeScript.

  This determines the import statement used in generated TypeScript files.
  Defaults to "zod" for standard npm package.
  Can be customized for different package managers or custom Zod builds.
  """
  def zod_import_path do
    Application.get_env(:ash_typescript, :zod_import_path)
  end

  @doc """
  Gets the suffix used for generated Zod schema constants.

  This determines the naming pattern for Zod schemas.
  Defaults to "Schema" (e.g., createTodoSchema).
  """
  def zod_schema_suffix do
    Application.get_env(:ash_typescript, :zod_schema_suffix)
  end

  @doc """
  Determines if Phoenix channel-based RPC actions should be generated.

  This controls whether channel functions are generated alongside fetch-based functions.
  Defaults to false.
  """
  def generate_phx_channel_rpc_actions? do
    Application.get_env(:ash_typescript, :generate_phx_channel_rpc_actions)
  end

  @doc """
  Determines whether to generate validation functions alongside RPC functions.

  This controls whether validation functions are generated alongside fetch-based functions.
  Defaults to false.
  """
  def generate_validation_functions? do
    Application.get_env(:ash_typescript, :generate_validation_functions)
  end

  @doc """
  Checks if RPC action hooks are enabled (either beforeRequest or afterRequest).

  Returns true if either beforeRequest or afterRequest hook is configured for RPC actions.
  """
  def rpc_action_hooks_enabled? do
    AshTypescript.rpc_action_before_request_hook() != nil ||
      AshTypescript.rpc_action_after_request_hook() != nil
  end

  @doc """
  Checks if RPC validation hooks are enabled (either beforeRequest or afterRequest).

  Returns true if either beforeRequest or afterRequest hook is configured for validations.
  """
  def rpc_validation_hooks_enabled? do
    AshTypescript.rpc_validation_before_request_hook() != nil ||
      AshTypescript.rpc_validation_after_request_hook() != nil
  end

  @doc """
  Checks if RPC action channel hooks are enabled (either beforeChannelPush or afterChannelResponse).

  Returns true if either beforeChannelPush or afterChannelResponse hook is configured for RPC actions.
  """
  def rpc_action_channel_hooks_enabled? do
    AshTypescript.rpc_action_before_channel_push_hook() != nil ||
      AshTypescript.rpc_action_after_channel_response_hook() != nil
  end

  @doc """
  Checks if RPC validation channel hooks are enabled (either beforeChannelPush or afterChannelResponse).

  Returns true if either beforeChannelPush or afterChannelResponse hook is configured for validations.
  """
  def rpc_validation_channel_hooks_enabled? do
    AshTypescript.rpc_validation_before_channel_push_hook() != nil ||
      AshTypescript.rpc_validation_after_channel_response_hook() != nil
  end

  @doc """
  Gets the Phoenix import path for generated TypeScript.

  This determines the import statement used for Phoenix channels in generated TypeScript files.
  Defaults to "phoenix" for standard npm package.
  Can be customized for different package managers or custom Phoenix builds.
  """
  def phoenix_import_path do
    Application.get_env(:ash_typescript, :phoenix_import_path)
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
    requires_tenant?(resource) and require_tenant_parameters?()
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
  @spec run_action(atom(), Plug.Conn.t(), map()) :: map()
  def run_action(otp_app, conn, params) do
    with {:ok, parsed_request} <- Pipeline.parse_request(otp_app, conn, params),
         {:ok, ash_result} <- Pipeline.execute_ash_action(parsed_request),
         {:ok, processed_result} <- Pipeline.process_result(ash_result, parsed_request) do
      Pipeline.format_output(%{success: true, data: processed_result}, parsed_request)
    else
      {:error, reason} ->
        %{success: false, errors: [ErrorBuilder.build_error_response(reason)]}
        |> Pipeline.format_output()
    end
  end

  @doc """
  Validates action parameters without execution.
  Used for form validation in the client.
  """
  @spec validate_action(atom(), Plug.Conn.t(), map()) ::
          {:ok, map()} | {:error, map()}
  def validate_action(otp_app, conn, params) do
    case Pipeline.parse_request(otp_app, conn, params, validation_mode?: true) do
      {:ok, parsed_request} ->
        validate_form_input(parsed_request)
        |> Pipeline.format_output(parsed_request)

      {:error, reason} ->
        %{success: false, errors: [ErrorBuilder.build_error_response(reason)]}
        |> Pipeline.format_output()
    end
  end

  defp validate_form_input(%{action: action, resource: resource, input: input} = request) do
    opts = [
      actor: request.actor,
      tenant: request.tenant,
      context: request.context
    ]

    case action.type do
      :read ->
        # For read actions, validate by building a query
        validate_read_action(resource, action, input, opts)

      action_type when action_type in [:update, :destroy] ->
        case Ash.get(resource, request.primary_key, opts) do
          {:ok, record} ->
            perform_form_validation(record, action.name, input, opts)

          {:error, error} ->
            %{success: false, errors: [ErrorBuilder.build_error_response(error)]}
        end

      _ ->
        perform_form_validation(resource, action.name, input, opts)
    end
  end

  defp validate_read_action(resource, action, input, opts) do
    # For read actions, validate by building a query
    query =
      resource
      |> Ash.Query.for_read(action.name, input, opts)

    # If we can build the query without errors, validation passes
    case query do
      %Ash.Query{errors: []} ->
        %{success: true}

      %Ash.Query{errors: errors} when errors != [] ->
        formatted_errors =
          errors
          |> Enum.map(fn error ->
            %{
              type: "validation_error",
              message: Exception.message(error)
            }
          end)

        %{success: false, errors: formatted_errors}

      _ ->
        %{success: true}
    end
  rescue
    e ->
      %{
        success: false,
        errors: [
          %{
            type: "validation_error",
            message: Exception.message(e)
          }
        ]
      }
  end

  defp perform_form_validation(record_or_resource, action_name, input, opts) do
    form_errors =
      record_or_resource
      |> AshPhoenix.Form.for_action(action_name, opts)
      |> AshPhoenix.Form.validate(input)
      |> AshPhoenix.Form.errors()

    if Enum.empty?(form_errors) do
      %{success: true}
    else
      formatted_errors =
        form_errors
        |> Enum.map(fn {field, messages} ->
          formatted_messages =
            messages
            |> List.wrap()
            |> Enum.map(&to_string/1)

          %{
            type: "validation_error",
            field: to_string(field),
            errors: formatted_messages
          }
        end)

      %{success: false, errors: formatted_errors}
    end
  end

  @doc """
  Runs a typed query for server-side rendering and data fetching.

  This function looks up a typed query by name and executes it with the configured fields,
  returning the data in the exact shape defined by the typed query. This is ideal for
  SSR controllers that need to pre-fetch data with type safety.

  ## Parameters
  - `otp_app` - The OTP application name
  - `typed_query_name` - The atom name of the typed query to execute
  - `params` - Map with optional `:input` and `:page` keys
  - `conn` - The Plug connection (for tenant context, etc.)

  ## Returns
  - `{:ok, data}` - Successfully executed typed query with processed results
  - `{:error, reason}` - Error during lookup or execution

  ## Example
      # In a Phoenix controller
      def index(conn, _params) do
        case AshTypescript.Rpc.run_typed_query(:my_app, :list_todos_user_page, %{}, conn) do
          %{"success" => true, "data" => todos} ->
            render(conn, "index.html", initial_todos: todos)
          %{"success" => false, "error" => reason} ->
            # Handle error appropriately
            send_resp(conn, 500, "Error loading data")
        end
      end
  """
  @spec run_typed_query(atom(), atom(), map(), Plug.Conn.t()) :: map()
  def run_typed_query(otp_app, typed_query_name, params \\ %{}, conn) do
    case find_typed_query(otp_app, typed_query_name) do
      {:ok, typed_query} ->
        rpc_params = %{
          "typed_query_action" => Atom.to_string(typed_query_name),
          "fields" => typed_query.fields
        }

        rpc_params =
          rpc_params
          |> maybe_add_param("input", params[:input])
          |> maybe_add_param("page", params[:page])
          |> maybe_add_param("filter", params[:filter])
          |> maybe_add_param("sort", params[:sort])

        run_action(otp_app, conn, rpc_params)

      error ->
        error
    end
  end

  defp find_typed_query(otp_app, typed_query_name) do
    otp_app
    |> Ash.Info.domains()
    |> Enum.reduce_while({:error, {:typed_query_not_found, typed_query_name}}, fn domain, _acc ->
      rpc_config = AshTypescript.Rpc.Info.typescript_rpc(domain)

      Enum.find_value(rpc_config, fn %{typed_queries: typed_queries} ->
        Enum.find(typed_queries, &(&1.name == typed_query_name))
      end)
      |> case do
        nil -> {:cont, {:error, {:typed_query_not_found, typed_query_name}}}
        found -> {:halt, {:ok, found}}
      end
    end)
  end

  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, key, value), do: Map.put(params, key, value)
end
