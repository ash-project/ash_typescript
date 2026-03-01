# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedController.Codegen.TypescriptStatic do
  @moduledoc """
  Generates static TypeScript code for typed controller routes.

  This includes:
  - Import statements (Zod, custom imports)
  - Hook context type definitions
  - TypedControllerConfig interface
  - executeTypedControllerRequest helper function
  """

  import AshTypescript.Helpers

  alias AshTypescript.Codegen.ImportResolver

  @doc """
  Generates all static TypeScript code for typed controller routes.

  Returns a string containing imports, config interface, and helper function.
  Only generates content when `typed_controller_mode() == :full`.

  ## Options

    * `:skip_zod` - When true, omits the Zod import (for split-file mode)
  """
  def generate_static_code(opts \\ []) do
    imports = generate_imports(opts)
    base_path_var = generate_base_path_variable(Keyword.get(opts, :base_path, ""))
    hook_context_type = generate_hook_context_type()
    config_interface = generate_config_interface()
    helper_function = generate_helper_function()

    [imports, base_path_var, hook_context_type, config_interface, helper_function]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  @doc """
  Generates a `_basePath` constant when a base path is configured.

  Returns an empty string when the base path is `""` (default).
  """
  def generate_base_path_variable(""), do: ""

  def generate_base_path_variable(base_path) do
    formatted = AshTypescript.Helpers.format_ts_value(base_path)
    "const _basePath = #{formatted};\n"
  end

  defp generate_imports(opts) do
    skip_zod = Keyword.get(opts, :skip_zod, false)
    output_file = Keyword.get(opts, :output_file)

    zod_import =
      if not skip_zod and AshTypescript.Rpc.generate_zod_schemas?() do
        zod_path = AshTypescript.Rpc.zod_import_path()
        "import { z } from \"#{zod_path}\";"
      else
        ""
      end

    config_imports =
      case AshTypescript.typed_controller_import_into_generated() do
        [] ->
          ""

        imports when is_list(imports) ->
          ImportResolver.resolve_custom_imports(output_file, imports)
      end

    [zod_import, config_imports]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
    |> case do
      "" -> ""
      imports_str -> imports_str <> "\n"
    end
  end

  defp generate_hook_context_type do
    if AshTypescript.typed_controller_hooks_enabled?() do
      context_type = AshTypescript.typed_controller_hook_context_type()

      """
      export type TypedControllerHookContext = #{context_type};
      """
    else
      ""
    end
  end

  defp generate_config_interface do
    hook_ctx_field =
      if AshTypescript.typed_controller_hooks_enabled?() do
        "\n  #{formatted_hook_ctx_field()}?: TypedControllerHookContext;"
      else
        ""
      end

    """
    /**
     * Configuration options for typed controller requests
     */
    export interface TypedControllerConfig {
      #{formatted_headers_field()}?: Record<string, string>;
      #{formatted_fetch_options_field()}?: RequestInit;
      #{formatted_custom_fetch_field()}?: (
        input: RequestInfo | URL,
        init?: RequestInit,
      ) => Promise<Response>;#{hook_ctx_field}
    }
    """
  end

  defp generate_helper_function do
    before_hook = AshTypescript.typed_controller_before_request_hook()
    after_hook = AshTypescript.typed_controller_after_request_hook()

    before_hook_code =
      if before_hook do
        """
            let processedConfig = config || {};
            if (#{before_hook}) {
              processedConfig = await #{before_hook}(actionName, processedConfig);
            }
        """
      else
        """
            const processedConfig = config || {};
        """
      end

    after_hook_code =
      if after_hook do
        """
            if (#{after_hook}) {
              await #{after_hook}(actionName, response, processedConfig);
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
     * Internal helper function for making typed controller requests
     */
    export async function executeTypedControllerRequest(
      url: string,
      method: string,
      actionName: string,
      body: string | undefined,
      config?: TypedControllerConfig,
    ): Promise<Response> {
    #{before_hook_code}
      const headers: Record<string, string> = {
        "Content-Type": "application/json",
        ...processedConfig.#{headers_field},
      };

      const fetchFunction = processedConfig.#{custom_fetch_field} || fetch;
      const fetchInit: RequestInit = {
        ...processedConfig.#{fetch_options_field},
        method,
        headers,
        ...(body !== undefined ? { body } : {}),
      };

      const response = await fetchFunction(url, fetchInit);

    #{after_hook_code}
      return response;
    }
    """
  end
end
