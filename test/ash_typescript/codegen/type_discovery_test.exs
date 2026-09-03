# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# A domain that carries the AshTypescript.Rpc extension but exposes none of its
# resources through `typescript_rpc`. Registered under a dedicated (fake) OTP
# app inside the tests below so the missing-RPC-config warning can be exercised
# without mutating the real `:ash_typescript` domain list.
defmodule AshTypescript.Codegen.TypeDiscoveryTest.MissingRpcConfigDomain do
  @moduledoc false
  use Ash.Domain, extensions: [AshTypescript.Rpc], validate_config_inclusion?: false

  typescript_rpc do
  end

  resources do
    resource AshTypescript.Test.Post
    resource AshTypescript.Test.PostComment
  end
end

defmodule AshTypescript.Codegen.TypeDiscoveryTest do
  use ExUnit.Case, async: true

  # Snapshot the global config this module mutates so it cannot leak into
  # later test modules.
  setup_all do
    AshTypescript.Test.TestHelpers.restore_application_env_on_exit([
      :warn_on_missing_rpc_config,
      :warn_on_non_rpc_references
    ])
  end

  alias AshTypescript.Codegen.TypeDiscovery
  alias AshTypescript.Codegen.TypeDiscoveryTest.MissingRpcConfigDomain

  # Dedicated OTP app so `Ash.Info.domains/1` resolves to the domain above
  # without touching `:ash_typescript`'s own configuration.
  @missing_config_app :ash_typescript_type_discovery_test

  describe "get_rpc_resources/1" do
    test "returns all RPC resources configured in domains" do
      rpc_resources = TypeDiscovery.get_rpc_resources(:ash_typescript)

      # These are configured in test/support/domain.ex
      assert AshTypescript.Test.Todo in rpc_resources
      assert AshTypescript.Test.TodoComment in rpc_resources
      assert AshTypescript.Test.User in rpc_resources
      assert AshTypescript.Test.UserSettings in rpc_resources
      assert AshTypescript.Test.OrgTodo in rpc_resources
      assert AshTypescript.Test.Task in rpc_resources

      # These are NOT configured as RPC resources
      refute AshTypescript.Test.TodoMetadata in rpc_resources
      refute AshTypescript.Test.NotExposed in rpc_resources
    end
  end

  describe "find_resources_missing_from_rpc_config/1" do
    test "finds resources with extension but not in typescript_rpc" do
      result = TypeDiscovery.find_resources_missing_from_rpc_config(:ash_typescript)

      assert is_list(result)
      assert Enum.all?(result, &is_atom/1)
    end

    test "reports resources carrying the extension that are absent from typescript_rpc" do
      register_missing_config_app()

      missing = TypeDiscovery.find_resources_missing_from_rpc_config(@missing_config_app, %{})

      # Both resources carry AshTypescript.Resource and neither is listed in the
      # domain's (empty) typescript_rpc block.
      assert AshTypescript.Resource in Spark.extensions(AshTypescript.Test.Post)
      assert AshTypescript.Resource in Spark.extensions(AshTypescript.Test.PostComment)

      assert AshTypescript.Test.Post in missing
      assert AshTypescript.Test.PostComment in missing
    end

    test "does not report resources that are configured for RPC" do
      # Todo carries the extension AND is exposed in test/support/domain.ex, so
      # its absence from the result is the rejection branch, not a missing
      # extension.
      assert AshTypescript.Resource in Spark.extensions(AshTypescript.Test.Todo)
      assert AshTypescript.Test.Todo in TypeDiscovery.get_rpc_resources(:ash_typescript)

      missing = TypeDiscovery.find_resources_missing_from_rpc_config(:ash_typescript)

      refute AshTypescript.Test.Todo in missing
    end

    test "does not report embedded resources" do
      register_missing_config_app()

      # Claim PostComment is embedded via the resource lookup - the only way to
      # drive the embedded rejection branch, since Ash refuses to let embedded
      # resources be listed in a domain.
      resource_lookup = %{
        AshTypescript.Test.PostComment => %Ash.Info.Manifest.Resource{
          name: "PostComment",
          module: AshTypescript.Test.PostComment,
          embedded?: true
        }
      }

      missing =
        TypeDiscovery.find_resources_missing_from_rpc_config(
          @missing_config_app,
          resource_lookup
        )

      assert AshTypescript.Test.Post in missing
      refute AshTypescript.Test.PostComment in missing

      # TodoMetadata carries the extension, is embedded, and is not exposed via
      # typescript_rpc - it must never show up as misconfigured.
      assert AshTypescript.Resource in Spark.extensions(AshTypescript.Test.TodoMetadata)
      assert Ash.Resource.Info.embedded?(AshTypescript.Test.TodoMetadata)

      refute AshTypescript.Test.TodoMetadata in TypeDiscovery.find_resources_missing_from_rpc_config(
               :ash_typescript
             )
    end
  end

  describe "build_rpc_warnings/1" do
    test "returns nil when all warnings disabled" do
      original_missing = Application.get_env(:ash_typescript, :warn_on_missing_rpc_config)
      original_non_rpc = Application.get_env(:ash_typescript, :warn_on_non_rpc_references)

      try do
        Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, false)
        Application.put_env(:ash_typescript, :warn_on_non_rpc_references, false)

        assert TypeDiscovery.build_rpc_warnings(:ash_typescript) == nil
      after
        if original_missing do
          Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, original_missing)
        else
          Application.delete_env(:ash_typescript, :warn_on_missing_rpc_config)
        end

        if original_non_rpc do
          Application.put_env(:ash_typescript, :warn_on_non_rpc_references, original_non_rpc)
        else
          Application.delete_env(:ash_typescript, :warn_on_non_rpc_references)
        end
      end
    end

    test "respects warn_on_missing_rpc_config flag" do
      original_missing = Application.get_env(:ash_typescript, :warn_on_missing_rpc_config)
      original_non_rpc = Application.get_env(:ash_typescript, :warn_on_non_rpc_references)

      try do
        Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, false)
        Application.put_env(:ash_typescript, :warn_on_non_rpc_references, true)

        output = TypeDiscovery.build_rpc_warnings(:ash_typescript)

        # The non-RPC references section still fires, so there IS output to
        # inspect - the missing-config section must simply be absent from it.
        assert output != nil
        refute output =~ "Found resources with AshTypescript.Resource extension"
        refute output =~ "not listed in any domain's typescript_rpc block"
      after
        if original_missing do
          Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, original_missing)
        else
          Application.delete_env(:ash_typescript, :warn_on_missing_rpc_config)
        end

        if original_non_rpc do
          Application.put_env(:ash_typescript, :warn_on_non_rpc_references, original_non_rpc)
        else
          Application.delete_env(:ash_typescript, :warn_on_non_rpc_references)
        end
      end
    end

    test "respects warn_on_non_rpc_references flag" do
      original_missing = Application.get_env(:ash_typescript, :warn_on_missing_rpc_config)
      original_non_rpc = Application.get_env(:ash_typescript, :warn_on_non_rpc_references)

      try do
        resource_lookup = AshTypescript.resource_lookup()
        rpc_resources = TypeDiscovery.get_rpc_resources(:ash_typescript)

        # Sanity check: with the flag on, this exact call DOES emit the section.
        Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, false)
        Application.put_env(:ash_typescript, :warn_on_non_rpc_references, true)

        enabled_output =
          TypeDiscovery.build_rpc_warnings(:ash_typescript, resource_lookup, rpc_resources)

        assert enabled_output =~ "Found non-RPC resources referenced by RPC resources"

        Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, true)
        Application.put_env(:ash_typescript, :warn_on_non_rpc_references, false)

        output =
          TypeDiscovery.build_rpc_warnings(:ash_typescript, resource_lookup, rpc_resources)

        assert output == nil,
               "expected no warnings at all: the non-RPC section is suppressed and no " <>
                 "resource with the extension is missing from a typescript_rpc block"
      after
        if original_missing do
          Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, original_missing)
        else
          Application.delete_env(:ash_typescript, :warn_on_missing_rpc_config)
        end

        if original_non_rpc do
          Application.put_env(:ash_typescript, :warn_on_non_rpc_references, original_non_rpc)
        else
          Application.delete_env(:ash_typescript, :warn_on_non_rpc_references)
        end
      end
    end

    test "non-RPC references warning states NO types are generated" do
      original_missing = Application.get_env(:ash_typescript, :warn_on_missing_rpc_config)
      original_non_rpc = Application.get_env(:ash_typescript, :warn_on_non_rpc_references)

      try do
        Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, false)
        Application.put_env(:ash_typescript, :warn_on_non_rpc_references, true)

        output = TypeDiscovery.build_rpc_warnings(:ash_typescript)

        assert output != nil
        assert output =~ "Found non-RPC resources referenced by RPC resources"
        assert output =~ "will NOT have TypeScript types or RPC functions generated"
        refute output =~ "will have basic TypeScript types generated"

        assert output =~
                 "If these resources should be accessible via RPC, add them to a domain's"

        assert output =~ "typescript_rpc block. Otherwise, you can ignore this warning"
      after
        if original_missing do
          Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, original_missing)
        else
          Application.delete_env(:ash_typescript, :warn_on_missing_rpc_config)
        end

        if original_non_rpc do
          Application.put_env(:ash_typescript, :warn_on_non_rpc_references, original_non_rpc)
        else
          Application.delete_env(:ash_typescript, :warn_on_non_rpc_references)
        end
      end
    end

    test "warnings are enabled by default" do
      original_missing = Application.get_env(:ash_typescript, :warn_on_missing_rpc_config)
      original_non_rpc = Application.get_env(:ash_typescript, :warn_on_non_rpc_references)

      try do
        Application.delete_env(:ash_typescript, :warn_on_missing_rpc_config)
        Application.delete_env(:ash_typescript, :warn_on_non_rpc_references)

        assert AshTypescript.warn_on_missing_rpc_config?() == true
        assert AshTypescript.warn_on_non_rpc_references?() == true
      after
        if original_missing do
          Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, original_missing)
        else
          Application.delete_env(:ash_typescript, :warn_on_missing_rpc_config)
        end

        if original_non_rpc do
          Application.put_env(:ash_typescript, :warn_on_non_rpc_references, original_non_rpc)
        else
          Application.delete_env(:ash_typescript, :warn_on_non_rpc_references)
        end
      end
    end

    test "configuration functions return correct values" do
      set_warning_flags(false, false)

      assert AshTypescript.warn_on_missing_rpc_config?() == false
      assert AshTypescript.warn_on_non_rpc_references?() == false

      Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, true)
      Application.put_env(:ash_typescript, :warn_on_non_rpc_references, true)

      assert AshTypescript.warn_on_missing_rpc_config?() == true
      assert AshTypescript.warn_on_non_rpc_references?() == true
    end
  end

  describe "non-RPC references warning content" do
    test "lists non-RPC referenced resources and excludes RPC resources" do
      set_warning_flags(false, true)

      output = non_rpc_references_warning()

      assert output != nil
      assert output =~ "Found non-RPC resources referenced by RPC resources:"

      # NotExposed is referenced by Todo but never exposed via typescript_rpc
      assert output =~ "   • AshTypescript.Test.NotExposed"

      # RPC resources are rejected before the message is built
      refute output =~ "   • AshTypescript.Test.Todo\n"
      refute output =~ "   • AshTypescript.Test.TodoComment\n"
      refute output =~ "   • AshTypescript.Test.User\n"
    end

    test "attributes each non-RPC resource to its referencing resource and field/relationship" do
      set_warning_flags(false, true)

      output = non_rpc_references_warning()

      assert output != nil
      assert output =~ "Referenced by:"

      # NotExposed is reached only through Todo's has_many relationship
      assert output =~ "AshTypescript.Test.Todo (relationship :not_exposed_items)"
    end

    test "excludes embedded resources" do
      set_warning_flags(false, true)

      output = non_rpc_references_warning()

      assert output != nil

      embedded_modules =
        AshTypescript.resource_lookup()
        |> Map.values()
        |> Enum.filter(& &1.embedded?)
        |> Enum.map(& &1.module)

      # Guard against a vacuous pass if the lookup ever stops carrying embeds
      assert AshTypescript.Test.TodoMetadata in embedded_modules

      for module <- embedded_modules do
        refute output =~ inspect(module),
               "embedded resource #{inspect(module)} should not be reported as a " <>
                 "non-RPC reference"
      end
    end
  end

  describe "missing RPC config warning content" do
    test "missing RPC config warning contains correct explanatory text" do
      set_warning_flags(true, false)
      register_missing_config_app()

      output = TypeDiscovery.build_rpc_warnings(@missing_config_app, %{}, [])

      assert output != nil

      # Header
      assert output =~ "Found resources with AshTypescript.Resource extension"
      assert output =~ "not listed in any domain's typescript_rpc block"

      # Offending resources
      assert output =~ "   • AshTypescript.Test.Post"
      assert output =~ "   • AshTypescript.Test.PostComment"

      # Explanation
      assert output =~ "These resources will not have TypeScript types generated"

      # Guidance
      assert output =~ "To fix this, add them to a domain's typescript_rpc block"

      # Generated example config snippet
      assert output =~ "   defmodule #{inspect(MissingRpcConfigDomain)} do"
      assert output =~ "     use Ash.Domain, extensions: [AshTypescript.Rpc]"
      assert output =~ "     typescript_rpc do"
      assert output =~ "       resource AshTypescript.Test."
    end

    test "warning message includes proper formatting" do
      set_warning_flags(true, true)
      register_missing_config_app()

      # Missing-config section comes from the fake app's domain, the non-RPC
      # section from the real resource lookup - so both sections fire.
      output =
        TypeDiscovery.build_rpc_warnings(
          @missing_config_app,
          AshTypescript.resource_lookup(),
          TypeDiscovery.get_rpc_resources(:ash_typescript)
        )

      assert output != nil
      assert output =~ "⚠️"
      assert output =~ "   •"
      assert output =~ "Found resources with AshTypescript.Resource extension"
      assert output =~ "Found non-RPC resources referenced by RPC resources"

      # The two sections are separated by a blank line
      assert output =~ "\n\n⚠️  Found non-RPC resources referenced by RPC resources:"
    end
  end

  # Builds only the non-RPC-references section, using the real app's lookup and
  # RPC resource list. Requires the missing-config warning to be disabled.
  defp non_rpc_references_warning do
    TypeDiscovery.build_rpc_warnings(
      :ash_typescript,
      AshTypescript.resource_lookup(),
      TypeDiscovery.get_rpc_resources(:ash_typescript)
    )
  end

  defp register_missing_config_app do
    original = Application.get_env(@missing_config_app, :ash_domains)
    on_exit(fn -> restore_env(@missing_config_app, :ash_domains, original) end)
    Application.put_env(@missing_config_app, :ash_domains, [MissingRpcConfigDomain])
  end

  defp set_warning_flags(missing?, non_rpc?) do
    original_missing = Application.get_env(:ash_typescript, :warn_on_missing_rpc_config)
    original_non_rpc = Application.get_env(:ash_typescript, :warn_on_non_rpc_references)

    on_exit(fn ->
      restore_env(:ash_typescript, :warn_on_missing_rpc_config, original_missing)
      restore_env(:ash_typescript, :warn_on_non_rpc_references, original_non_rpc)
    end)

    Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, missing?)
    Application.put_env(:ash_typescript, :warn_on_non_rpc_references, non_rpc?)
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
