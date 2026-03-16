# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Inline resource for warn_missing_returns test — publication intentionally
# omits `returns` so the verifier warns. Defined outside the test module so
# this file is self-contained (doesn't depend on codegen_test.exs).
defmodule AshTypescript.Test.TypedChannel.VerifierNoReturnsItem do
  @moduledoc false
  use Ash.Resource, domain: nil, notifiers: [Ash.Notifier.PubSub]

  pub_sub do
    module AshTypescript.Test.TestEndpoint
    prefix "verifier_no_returns"

    publish :destroy, [:id],
      event: "thing_gone",
      public?: true

    # intentionally no `returns`
  end

  attributes do
    uuid_primary_key :id
  end

  actions do
    defaults [:destroy]
  end
end

defmodule AshTypescript.Test.TypedChannel.VerifierNoReturnsChannel do
  @moduledoc false
  use AshTypescript.TypedChannel

  typed_channel do
    topic "verifier_things:*"

    resource AshTypescript.Test.TypedChannel.VerifierNoReturnsItem do
      publish(:thing_gone)
    end
  end
end

# Inline resource with public?: false on its publication.
defmodule AshTypescript.Test.TypedChannel.VerifierNotPublicItem do
  @moduledoc false
  use Ash.Resource, domain: nil, notifiers: [Ash.Notifier.PubSub]

  pub_sub do
    module AshTypescript.Test.TestEndpoint
    prefix "verifier_not_public"

    publish :destroy, [:id],
      event: "secret_removed",
      returns: :string,
      transform: fn n -> n.data.id end

    # intentionally no `public?: true`
  end

  attributes do
    uuid_primary_key :id
  end

  actions do
    defaults [:destroy]
  end
end

defmodule AshTypescript.Test.TypedChannel.VerifierNotPublicChannel do
  @moduledoc false
  use AshTypescript.TypedChannel

  typed_channel do
    topic "verifier_secret:*"

    resource AshTypescript.Test.TypedChannel.VerifierNotPublicItem do
      publish(:secret_removed)
    end
  end
end

defmodule AshTypescript.TypedChannel.VerifyTypedChannelTest do
  use ExUnit.Case

  alias AshTypescript.TypedChannel.Verifiers.VerifyTypedChannel

  @moduletag :ash_typescript

  describe "valid typed channel" do
    test "OrgChannel passes verification" do
      assert :ok = VerifyTypedChannel.verify(AshTypescript.Test.OrgChannel.spark_dsl_config())
    end

    test "ContentFeedChannel passes verification" do
      assert :ok =
               VerifyTypedChannel.verify(AshTypescript.Test.ContentFeedChannel.spark_dsl_config())
    end
  end

  describe "verify_events_exist" do
    @describetag :generates_warnings

    test "rejects event that does not match any publication" do
      defmodule ChannelWithMissingEvent do
        use AshTypescript.TypedChannel

        typed_channel do
          topic "missing:*"

          resource AshTypescript.Test.ChannelItem do
            publish(:item_created)
            publish(:nonexistent_event)
          end
        end
      end

      result = VerifyTypedChannel.verify(ChannelWithMissingEvent.spark_dsl_config())

      assert {:error, %Spark.Error.DslError{message: message}} = result
      assert message =~ "No publication with event :nonexistent_event"
      assert message =~ inspect(AshTypescript.Test.ChannelItem)
    end
  end

  describe "verify_unique_event_names" do
    @describetag :generates_warnings

    test "rejects duplicate event names across resources in the same channel" do
      defmodule DuplicateEventItem do
        @moduledoc false
        use Ash.Resource, domain: nil, notifiers: [Ash.Notifier.PubSub]

        pub_sub do
          module AshTypescript.Test.TestEndpoint
          prefix "dup_items"

          publish :create, [:id],
            event: "item_created",
            public?: true,
            returns: :string,
            transform: fn n -> n.data.id end
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          defaults [:create]
        end
      end

      defmodule ChannelWithDuplicateEvents do
        use AshTypescript.TypedChannel

        typed_channel do
          topic "dup:*"

          resource AshTypescript.Test.ChannelItem do
            publish(:item_created)
          end

          resource DuplicateEventItem do
            publish(:item_created)
          end
        end
      end

      result = VerifyTypedChannel.verify(ChannelWithDuplicateEvents.spark_dsl_config())

      assert {:error, %Spark.Error.DslError{message: message}} = result
      assert message =~ "Duplicate event names"
      assert message =~ "item_created"
    end
  end

  describe "warn_missing_returns" do
    test "warns when publication has no returns type" do
      warnings =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          result =
            VerifyTypedChannel.verify(
              AshTypescript.Test.TypedChannel.VerifierNoReturnsChannel.spark_dsl_config()
            )

          assert :ok = result
        end)

      assert warnings =~ "does not have `returns` set"
      assert warnings =~ "thing_gone"
    end

    test "warns when publication is not marked public?" do
      warnings =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          result =
            VerifyTypedChannel.verify(
              AshTypescript.Test.TypedChannel.VerifierNotPublicChannel.spark_dsl_config()
            )

          assert :ok = result
        end)

      assert warnings =~ "is not marked `public?: true`"
      assert warnings =~ "secret_removed"
    end
  end
end
