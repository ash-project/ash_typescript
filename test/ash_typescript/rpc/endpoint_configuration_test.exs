# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.EndpointConfigurationTest do
  use ExUnit.Case, async: false
  alias AshTypescript.Rpc.Codegen

  setup do
    Application.put_env(:ash_typescript, :enable_namespace_files, false)
    :ok
  end

  describe "format_endpoint_for_typescript/1" do
    test "formats string endpoint as quoted literal" do
      assert Codegen.format_endpoint_for_typescript("/rpc/run") == "\"/rpc/run\""
    end

    test "formats custom string endpoint as quoted literal" do
      assert Codegen.format_endpoint_for_typescript("http://localhost:4000/api/rpc") ==
               "\"http://localhost:4000/api/rpc\""
    end

    test "formats runtime expression as-is" do
      assert Codegen.format_endpoint_for_typescript({:runtime_expr, "getRunEndpoint()"}) ==
               "getRunEndpoint()"
    end

    test "formats namespaced runtime expression as-is" do
      assert Codegen.format_endpoint_for_typescript(
               {:runtime_expr, "CustomTypes.getRunEndpoint()"}
             ) == "CustomTypes.getRunEndpoint()"
    end

    test "formats deeply namespaced runtime expression as-is" do
      assert Codegen.format_endpoint_for_typescript(
               {:runtime_expr, "Config.Endpoints.getRunEndpoint()"}
             ) == "Config.Endpoints.getRunEndpoint()"
    end
  end

  describe "integration with generate_typescript_types" do
    test "generates correct TypeScript with string endpoints" do
      {:ok, generated} =
        Codegen.generate_typescript_types(:ash_typescript,
          run_endpoint: "/rpc/run",
          validate_endpoint: "/rpc/validate"
        )

      # Endpoints are now embedded in the helper functions, not passed as parameters
      # Check that the helpers contain the endpoints in their fetch calls
      assert generated =~ ~r/function executeActionRpcRequest.*?fetch.*?"\/rpc\/run"/s
      assert generated =~ ~r/function executeValidationRpcRequest.*?fetch.*?"\/rpc\/validate"/s
    end

    test "generates correct TypeScript with runtime expression endpoints" do
      {:ok, generated} =
        Codegen.generate_typescript_types(:ash_typescript,
          run_endpoint: {:runtime_expr, "CustomTypes.getRunEndpoint()"},
          validate_endpoint: {:runtime_expr, "CustomTypes.getValidateEndpoint()"}
        )

      # Endpoints are now embedded in the helper functions
      # Check that the helpers contain the runtime expressions in their fetch calls
      assert generated =~
               ~r/function executeActionRpcRequest.*?fetch.*?CustomTypes\.getRunEndpoint\(\)/s

      assert generated =~
               ~r/function executeValidationRpcRequest.*?fetch.*?CustomTypes\.getValidateEndpoint\(\)/s

      # Should NOT contain quoted versions of runtime expressions
      refute generated =~ ~r/fetch.*?"CustomTypes/
    end

    test "generates correct TypeScript with mixed endpoint types" do
      {:ok, generated} =
        Codegen.generate_typescript_types(:ash_typescript,
          run_endpoint: {:runtime_expr, "CustomTypes.getRunEndpoint()"},
          validate_endpoint: "/rpc/validate"
        )

      # Endpoints are now embedded in the helper functions
      # run_endpoint should be a runtime expression in executeActionRpcRequest
      assert generated =~
               ~r/function executeActionRpcRequest.*?fetch.*?CustomTypes\.getRunEndpoint\(\)/s

      # validate_endpoint should be a string literal in executeValidationRpcRequest
      assert generated =~ ~r/function executeValidationRpcRequest.*?fetch.*?"\/rpc\/validate"/s
    end
  end
end
