# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.TypescriptStatic do
  @moduledoc """
  Generates static TypeScript code that doesn't depend on specific resources.

  This includes:
  - Import statements (Zod, Phoenix Channel, custom imports)
  - Hook context type definitions
  - Utility types (TypedSchema, InferResult, pagination helpers, etc.)
  - Helper functions (CSRF token, RPC request executors)
  """

  import AshTypescript.Helpers

  @doc """
  Generates TypeScript import statements based on configuration.

  Includes:
  - Zod import (if zod schemas enabled and not skipped)
  - Phoenix Channel import (if channel RPC actions enabled)
  - Custom imports from application config

  ## Options

    * `:skip_zod` - When true, omits the Zod import (for split-file mode where Zod is in ash_zod.ts)
  """
  def generate_imports(opts \\ []) do
    skip_zod = Keyword.get(opts, :skip_zod, false)

    zod_import =
      if not skip_zod and AshTypescript.Rpc.generate_zod_schemas?() do
        zod_path = AshTypescript.Rpc.zod_import_path()
        "import { z } from \"#{zod_path}\";"
      else
        ""
      end

    phoenix_import =
      if AshTypescript.Rpc.generate_phx_channel_rpc_actions?() do
        phoenix_path = AshTypescript.Rpc.phoenix_import_path()
        "import { Channel } from \"#{phoenix_path}\";"
      else
        ""
      end

    config_imports =
      case Application.get_env(:ash_typescript, :import_into_generated) do
        nil ->
          ""

        imports when is_list(imports) ->
          imports
          |> Enum.map(fn import_config ->
            import_name = Map.get(import_config, :import_name)
            file_path = Map.get(import_config, :file)

            if import_name && file_path do
              "import * as #{import_name} from \"#{file_path}\";"
            else
              ""
            end
          end)
          |> Enum.reject(&(&1 == ""))
          |> Enum.join("\n")

        _ ->
          ""
      end

    all_imports =
      [zod_import, phoenix_import, config_imports]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")
      |> case do
        "" -> ""
        imports_str -> imports_str <> "\n"
      end

    all_imports
  end

  @doc """
  Generates TypeScript type definitions for hook context types.

  Hook context types are conditionally generated based on:
  - Whether hooks are enabled for each category
  - Whether a context type is configured
  """
  def generate_hook_context_types(hook_config) do
    action_context_type = Map.get(hook_config, :rpc_action_hook_context_type)
    validation_context_type = Map.get(hook_config, :rpc_validation_hook_context_type)
    action_channel_context_type = Map.get(hook_config, :rpc_action_channel_hook_context_type)

    validation_channel_context_type =
      Map.get(hook_config, :rpc_validation_channel_hook_context_type)

    action_hooks_enabled = AshTypescript.Rpc.rpc_action_hooks_enabled?()
    validation_hooks_enabled = AshTypescript.Rpc.rpc_validation_hooks_enabled?()
    action_channel_hooks_enabled = AshTypescript.Rpc.rpc_action_channel_hooks_enabled?()
    validation_channel_hooks_enabled = AshTypescript.Rpc.rpc_validation_channel_hooks_enabled?()

    parts = []

    parts =
      if action_hooks_enabled and action_context_type != nil and action_context_type != "" do
        parts ++
          [
            """
            // RPC Action Hook Context Type
            export type ActionHookContext = #{action_context_type};
            """
          ]
      else
        parts
      end

    parts =
      if validation_hooks_enabled and validation_context_type != nil and
           validation_context_type != "" do
        parts ++
          [
            """
            // RPC Validation Hook Context Type
            export type ValidationHookContext = #{validation_context_type};
            """
          ]
      else
        parts
      end

    parts =
      if action_channel_hooks_enabled and action_channel_context_type != nil and
           action_channel_context_type != "" do
        parts ++
          [
            """
            // RPC Action Channel Hook Context Type
            export type ActionChannelHookContext = #{action_channel_context_type};
            """
          ]
      else
        parts
      end

    parts =
      if validation_channel_hooks_enabled and validation_channel_context_type != nil and
           validation_channel_context_type != "" do
        parts ++
          [
            """
            // RPC Validation Channel Hook Context Type
            export type ValidationChannelHookContext = #{validation_channel_context_type};
            """
          ]
      else
        parts
      end

    if parts == [] do
      ""
    else
      Enum.join(parts, "\n") |> String.trim()
    end
  end

  @doc """
  Generates TypeScript helper functions and configuration interfaces.

  Includes:
  - Configuration interfaces (ActionConfig, ValidationConfig, etc.)
  - CSRF token helpers
  - RPC request execution functions
  - Channel push execution functions
  """
  def generate_helper_functions(hook_config, endpoint_process, endpoint_validate) do
    action_before_hook = Map.get(hook_config, :rpc_action_before_request_hook)
    action_after_hook = Map.get(hook_config, :rpc_action_after_request_hook)
    validation_before_hook = Map.get(hook_config, :rpc_validation_before_request_hook)
    validation_after_hook = Map.get(hook_config, :rpc_validation_after_request_hook)
    action_channel_before_hook = Map.get(hook_config, :rpc_action_before_channel_push_hook)
    action_channel_after_hook = Map.get(hook_config, :rpc_action_after_channel_response_hook)

    validation_channel_before_hook =
      Map.get(hook_config, :rpc_validation_before_channel_push_hook)

    validation_channel_after_hook =
      Map.get(hook_config, :rpc_validation_after_channel_response_hook)

    action_hook_context_type =
      Map.get(hook_config, :rpc_action_hook_context_type, "Record<string, any>")

    validation_hook_context_type =
      Map.get(hook_config, :rpc_validation_hook_context_type, "Record<string, any>")

    action_channel_hook_context_type =
      Map.get(hook_config, :rpc_action_channel_hook_context_type, "Record<string, any>")

    validation_channel_hook_context_type =
      Map.get(hook_config, :rpc_validation_channel_hook_context_type, "Record<string, any>")

    action_helper =
      generate_action_rpc_request_helper(
        endpoint_process,
        action_before_hook,
        action_after_hook
      )

    validation_helper =
      if AshTypescript.Rpc.generate_validation_functions?() do
        generate_validation_rpc_request_helper(
          endpoint_validate,
          validation_before_hook,
          validation_after_hook
        )
      else
        ""
      end

    action_channel_helper =
      if AshTypescript.Rpc.generate_phx_channel_rpc_actions?() do
        generate_action_channel_push_helper(
          "run",
          action_channel_before_hook,
          action_channel_after_hook
        )
      else
        ""
      end

    validation_channel_helper =
      if AshTypescript.Rpc.generate_validation_functions?() and
           AshTypescript.Rpc.generate_phx_channel_rpc_actions?() do
        generate_validation_channel_push_helper(
          "validate",
          validation_channel_before_hook,
          validation_channel_after_hook
        )
      else
        ""
      end

    validation_config_interface =
      if AshTypescript.Rpc.generate_validation_functions?() do
        """

        /**
         * Configuration options for validation RPC requests
         */
        export interface ValidationConfig {
          // Request data
          #{formatted_input_field()}?: Record<string, any>;

          // HTTP customization
          #{formatted_headers_field()}?: Record<string, string>;
          #{formatted_fetch_options_field()}?: RequestInit;
          #{formatted_custom_fetch_field()}?: (
            input: RequestInfo | URL,
            init?: RequestInit,
          ) => Promise<Response>;

          // Hook context
          #{formatted_hook_ctx_field()}?: #{validation_hook_context_type};
        }
        """
      else
        ""
      end

    action_channel_config_interface =
      if AshTypescript.Rpc.generate_phx_channel_rpc_actions?() do
        """

        /**
         * Configuration options for action channel RPC requests
         */
        export interface ActionChannelConfig {
          // Request data
          #{formatted_input_field()}?: Record<string, any>;
          #{formatted_identity_field()}?: any;
          #{formatted_fields_field()}?: ReadonlyArray<string | Record<string, any>>;
          #{formatted_filter_field()}?: Record<string, any>;
          #{formatted_sort_field()}?: string;
          #{formatted_page_field()}?:
            | {
                #{formatted_limit_field()}?: number;
                #{formatted_offset_field()}?: number;
                #{formatted_count_field()}?: boolean;
              }
            | {
                #{formatted_limit_field()}?: number;
                #{formatted_after_field()}?: string;
                #{formatted_before_field()}?: string;
              };

          // Metadata
          #{formatted_metadata_fields_field()}?: ReadonlyArray<string>;

          // Channel-specific
          #{formatted_channel_field()}: any; // Phoenix Channel
          #{formatted_result_handler_field()}: (result: any) => void;
          #{formatted_error_handler_field()}?: (error: any) => void;
          #{formatted_timeout_handler_field()}?: () => void;
          #{formatted_timeout_field()}?: number;

          // Multitenancy
          #{formatted_tenant_field()}?: string;

          // Hook context
          #{formatted_hook_ctx_field()}?: #{action_channel_hook_context_type};
        }
        """
      else
        ""
      end

    validation_channel_config_interface =
      if AshTypescript.Rpc.generate_validation_functions?() and
           AshTypescript.Rpc.generate_phx_channel_rpc_actions?() do
        """

        /**
         * Configuration options for validation channel RPC requests
         */
        export interface ValidationChannelConfig {
          // Request data
          #{formatted_input_field()}?: Record<string, any>;
          #{formatted_identity_field()}?: any;

          // Channel-specific
          #{formatted_channel_field()}: any; // Phoenix Channel
          #{formatted_result_handler_field()}: (result: any) => void;
          #{formatted_error_handler_field()}?: (error: any) => void;
          #{formatted_timeout_handler_field()}?: () => void;
          #{formatted_timeout_field()}?: number;

          // Multitenancy
          #{formatted_tenant_field()}?: string;

          // Hook context
          #{formatted_hook_ctx_field()}?: #{validation_channel_hook_context_type};
        }
        """
      else
        ""
      end

    """
    // Helper Functions

    /**
     * Configuration options for action RPC requests
     */
    export interface ActionConfig {
      // Request data
      #{formatted_input_field()}?: Record<string, any>;
      #{formatted_identity_field()}?: any;
      #{formatted_fields_field()}?: Array<string | Record<string, any>>; // Field selection
      #{formatted_filter_field()}?: Record<string, any>; // Filter options (for reads)
      #{formatted_sort_field()}?: string; // Sort options
      #{formatted_page_field()}?:
        | {
            // Offset-based pagination
            #{formatted_limit_field()}?: number;
            #{formatted_offset_field()}?: number;
            #{formatted_count_field()}?: boolean;
          }
        | {
            // Keyset pagination
            #{formatted_limit_field()}?: number;
            #{formatted_after_field()}?: string;
            #{formatted_before_field()}?: string;
          };

      // Metadata
      #{formatted_metadata_fields_field()}?: ReadonlyArray<string>;

      // HTTP customization
      #{formatted_headers_field()}?: Record<string, string>; // Custom headers
      #{formatted_fetch_options_field()}?: RequestInit; // Fetch options (signal, cache, etc.)
      #{formatted_custom_fetch_field()}?: (
        input: RequestInfo | URL,
        init?: RequestInit,
      ) => Promise<Response>;

      // Multitenancy
      #{formatted_tenant_field()}?: string; // Tenant parameter

      // Hook context
      #{formatted_hook_ctx_field()}?: #{action_hook_context_type};
    }
    #{validation_config_interface}
    #{action_channel_config_interface}
    #{validation_channel_config_interface}

    /**
     * Gets the CSRF token from the page's meta tag
     * Returns null if no CSRF token is found
     */
    export function getPhoenixCSRFToken(): string | null {
      return document
        ?.querySelector("meta[name='csrf-token']")
        ?.getAttribute("content") || null;
    }

    /**
     * Builds headers object with CSRF token for Phoenix applications
     * Returns headers object with X-CSRF-Token (if available)
     */
    export function buildCSRFHeaders(headers: Record<string, string> = {}): Record<string, string> {
      const csrfToken = getPhoenixCSRFToken();
      if (csrfToken) {
        headers["X-CSRF-Token"] = csrfToken;
      }

      return headers;
    }

    #{action_helper}

    #{validation_helper}

    #{action_channel_helper}

    #{validation_channel_helper}
    """
  end

  defp generate_action_rpc_request_helper(endpoint, before_hook, after_hook) do
    generate_rpc_request_helper_impl(
      "executeActionRpcRequest",
      "action RPC request",
      "ActionConfig",
      endpoint,
      before_hook,
      after_hook
    )
  end

  defp generate_validation_rpc_request_helper(endpoint, before_hook, after_hook) do
    generate_rpc_request_helper_impl(
      "executeValidationRpcRequest",
      "validation RPC request",
      "ValidationConfig",
      endpoint,
      before_hook,
      after_hook
    )
  end

  defp generate_rpc_request_helper_impl(
         function_name,
         description,
         config_type,
         endpoint,
         before_hook,
         after_hook
       ) do
    success_field = format_output_field(:success)
    errors_field = format_output_field(:errors)
    type_field = formatted_error_type_field()
    message_field = formatted_error_message_field()
    short_message_field = formatted_error_short_message_field()
    vars_field = formatted_error_vars_field()
    fields_field = formatted_error_fields_field()
    path_field = formatted_error_path_field()
    details_field = formatted_error_details_field()

    before_hook_code =
      if before_hook do
        """
            let processedConfig = config;
            if (#{before_hook}) {
              processedConfig = await #{before_hook}(payload.action, config);
            }
        """
      else
        """
            const processedConfig = config;
        """
      end

    after_hook_code =
      if after_hook do
        """
            if (#{after_hook}) {
              await #{after_hook}(payload.action, response, result, processedConfig);
            }
        """
      else
        ""
      end

    headers_field = formatted_headers_field()
    custom_fetch_field = formatted_custom_fetch_field()
    fetch_options_field = formatted_fetch_options_field()

    """
    /**
     * Internal helper function for making #{description}s
     * Handles hooks, request configuration, fetch execution, and error handling
     * @param config Configuration matching #{config_type}
     */
    export async function #{function_name}<T>(
      payload: Record<string, any>,
      config: #{config_type}
    ): Promise<T> {
    #{before_hook_code}
      const headers: Record<string, string> = {
        "Content-Type": "application/json",
        ...processedConfig.#{headers_field},
        ...config.#{headers_field},
      };

      const fetchFunction = config.#{custom_fetch_field} || processedConfig.#{custom_fetch_field} || fetch;
      const fetchOptions: RequestInit = {
        ...processedConfig.#{fetch_options_field},
        ...config.#{fetch_options_field},
        method: "POST",
        headers,
        body: JSON.stringify(payload),
      };

      const response = await fetchFunction(#{endpoint}, fetchOptions);
      const result = response.ok ? await response.json() : null;

    #{after_hook_code}
      if (!response.ok) {
        return {
          #{success_field}: false,
          #{errors_field}: [
            {
              #{type_field}: "network_error",
              #{message_field}: `Network request failed: ${response.statusText}`,
              #{short_message_field}: "Network error",
              #{vars_field}: { statusCode: response.status, statusText: response.statusText },
              #{fields_field}: [],
              #{path_field}: [],
              #{details_field}: { statusCode: response.status }
            }
          ],
        } as T;
      }

      return result as T;
    }
    """
  end

  defp generate_action_channel_push_helper(event, before_hook, after_hook) do
    generate_channel_push_helper_impl(
      "executeActionChannelPush",
      "action channel push",
      "ActionChannelConfig",
      event,
      before_hook,
      after_hook
    )
  end

  defp generate_validation_channel_push_helper(event, before_hook, after_hook) do
    generate_channel_push_helper_impl(
      "executeValidationChannelPush",
      "validation channel push",
      "ValidationChannelConfig",
      event,
      before_hook,
      after_hook
    )
  end

  defp generate_channel_push_helper_impl(
         function_name,
         description,
         config_type,
         event,
         before_hook,
         after_hook
       ) do
    before_hook_code =
      if before_hook do
        """
            let processedConfig = config;
            if (#{before_hook}) {
              processedConfig = await #{before_hook}(payload.action, config);
            }
        """
      else
        """
            const processedConfig = config;
        """
      end

    after_ok_hook_code =
      if after_hook do
        """
              if (#{after_hook}) {
                await #{after_hook}(payload.action, "ok", result, processedConfig);
              }
        """
      else
        ""
      end

    after_error_hook_code =
      if after_hook do
        """
              if (#{after_hook}) {
                await #{after_hook}(payload.action, "error", error, processedConfig);
              }
        """
      else
        ""
      end

    after_timeout_hook_code =
      if after_hook do
        """
              if (#{after_hook}) {
                await #{after_hook}(payload.action, "timeout", undefined, processedConfig);
              }
        """
      else
        ""
      end

    result_handler_field = formatted_result_handler_field()
    error_handler_field = formatted_error_handler_field()
    timeout_handler_field = formatted_timeout_handler_field()

    """
    /**
     * Internal helper function for making #{description} requests
     * Handles hooks and channel push with receive handlers
     * @param config Configuration matching #{config_type}
     */
    export async function #{function_name}<T>(
      channel: any,
      payload: Record<string, any>,
      timeout: number | undefined,
      config: #{config_type}
    ) {
    #{before_hook_code}
      const effectiveTimeout = timeout;

      channel
        .push("#{event}", payload, effectiveTimeout)
        .receive("ok", async (result: T) => {
    #{after_ok_hook_code}
          config.#{result_handler_field}(result);
        })
        .receive("error", async (error: any) => {
    #{after_error_hook_code}
          (config.#{error_handler_field}
            ? config.#{error_handler_field}
            : (error: any) => {
                console.error(
                  \`An error occurred while running action \${payload.action}:\`,
                  error
                );
              })(error);
        })
        .receive("timeout", async () => {
    #{after_timeout_hook_code}
          (config.#{timeout_handler_field}
            ? config.#{timeout_handler_field}
            : () => {
                console.error(\`Timeout occurred while running action \${payload.action}\`);
              })();
        });
    }
    """
  end
end
