# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.EndpointConfigurationTest do
  use ExUnit.Case, async: false
  alias AshTypescript.Rpc.Codegen

  describe "format_endpoint_for_typescript/1" do
    test "formats string endpoint as quoted literal" do
      assert Codegen.format_endpoint_for_typescript("/rpc/run") == "\"/rpc/run\""
    end

    test "formats custom string endpoint as quoted literal" do
      assert Codegen.format_endpoint_for_typescript("http://localhost:4000/api/rpc") ==
               "\"http://localhost:4000/api/rpc\""
    end

    test "formats function reference as function call" do
      assert Codegen.format_endpoint_for_typescript({:imported_ts_func, "getRunEndpoint"}) ==
               "getRunEndpoint()"
    end

    test "formats namespaced function reference as function call" do
      assert Codegen.format_endpoint_for_typescript(
               {:imported_ts_func, "CustomTypes.getRunEndpoint"}
             ) == "CustomTypes.getRunEndpoint()"
    end

    test "formats deeply namespaced function reference" do
      assert Codegen.format_endpoint_for_typescript(
               {:imported_ts_func, "Config.Endpoints.getRunEndpoint"}
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

      # Should contain the string literal in fetch call
      assert String.contains?(generated, ~s[fetchFunction("/rpc/run"])
      assert String.contains?(generated, ~s[fetchFunction("/rpc/validate"])
    end

    test "generates correct TypeScript with function reference endpoints" do
      {:ok, generated} =
        Codegen.generate_typescript_types(:ash_typescript,
          run_endpoint: {:imported_ts_func, "CustomTypes.getRunEndpoint"},
          validate_endpoint: {:imported_ts_func, "CustomTypes.getValidateEndpoint"}
        )

      # Should contain the function call (without quotes) in fetch call
      assert String.contains?(generated, "fetchFunction(CustomTypes.getRunEndpoint()")
      assert String.contains?(generated, "fetchFunction(CustomTypes.getValidateEndpoint()")

      # Should NOT contain quoted versions
      refute String.contains?(generated, ~s[fetchFunction("CustomTypes])
    end

    test "generates correct TypeScript with mixed endpoint types" do
      {:ok, generated} =
        Codegen.generate_typescript_types(:ash_typescript,
          run_endpoint: {:imported_ts_func, "CustomTypes.getRunEndpoint"},
          validate_endpoint: "/rpc/validate"
        )

      # run_endpoint should be a function call
      assert String.contains?(generated, "fetchFunction(CustomTypes.getRunEndpoint()")

      # validate_endpoint should be a string literal
      assert String.contains?(generated, ~s[fetchFunction("/rpc/validate"])
    end
  end
end
