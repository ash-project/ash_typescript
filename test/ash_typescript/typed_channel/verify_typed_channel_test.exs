# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

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

    test "TrackerChannel with calc transforms passes verification" do
      assert :ok =
               VerifyTypedChannel.verify(AshTypescript.Test.TrackerChannel.spark_dsl_config())
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
    # The fixtures below intentionally omit `returns` / `public?` so the verifier
    # warns. They're defined inside the capture closure — at runtime, rather than
    # at module level — so the verifier's `@after_verify` warning is captured here
    # instead of leaking into `mix test` output at compile time.
    test "warns when publication has no returns type" do
      warnings =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          defmodule NoReturnsItem do
            @moduledoc false
            use Ash.Resource, domain: nil, notifiers: [Ash.Notifier.PubSub]

            pub_sub do
              module AshTypescript.Test.TestEndpoint
              prefix "verifier_no_returns"

              publish :destroy, [:id], event: "thing_gone", public?: true
              # intentionally no `returns`
            end

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:destroy]
            end
          end

          defmodule NoReturnsChannel do
            @moduledoc false
            use AshTypescript.TypedChannel

            typed_channel do
              topic "verifier_things:*"

              resource NoReturnsItem do
                publish(:thing_gone)
              end
            end
          end

          assert :ok = VerifyTypedChannel.verify(NoReturnsChannel.spark_dsl_config())
        end)

      assert warnings =~ "does not have `returns` set"
      assert warnings =~ "thing_gone"
    end

    test "warns when publication is not marked public?" do
      warnings =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          defmodule NotPublicItem do
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

          defmodule NotPublicChannel do
            @moduledoc false
            use AshTypescript.TypedChannel

            typed_channel do
              topic "verifier_secret:*"

              resource NotPublicItem do
                publish(:secret_removed)
              end
            end
          end

          assert :ok = VerifyTypedChannel.verify(NotPublicChannel.spark_dsl_config())
        end)

      assert warnings =~ "is not marked `public?: true`"
      assert warnings =~ "secret_removed"
    end

    test "stays silent when warn_on_missing_channel_returns is false" do
      set_flag_false(:warn_on_missing_channel_returns)

      warnings =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          defmodule QuietNoReturnsItem do
            @moduledoc false
            use Ash.Resource, domain: nil, notifiers: [Ash.Notifier.PubSub]

            pub_sub do
              module AshTypescript.Test.TestEndpoint
              prefix "quiet_no_returns"

              publish :destroy, [:id], event: "quiet_gone", public?: true
            end

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:destroy]
            end
          end

          defmodule QuietNoReturnsChannel do
            @moduledoc false
            use AshTypescript.TypedChannel

            typed_channel do
              topic "quiet_things:*"

              resource QuietNoReturnsItem do
                publish(:quiet_gone)
              end
            end
          end

          assert :ok = VerifyTypedChannel.verify(QuietNoReturnsChannel.spark_dsl_config())
        end)

      refute warnings =~ "does not have `returns` set"
    end

    test "stays silent when warn_on_non_public_publications is false" do
      set_flag_false(:warn_on_non_public_publications)

      warnings =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          defmodule QuietNotPublicItem do
            @moduledoc false
            use Ash.Resource, domain: nil, notifiers: [Ash.Notifier.PubSub]

            pub_sub do
              module AshTypescript.Test.TestEndpoint
              prefix "quiet_not_public"

              publish :destroy, [:id],
                event: "quiet_secret",
                returns: :string,
                transform: fn n -> n.data.id end
            end

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:destroy]
            end
          end

          defmodule QuietNotPublicChannel do
            @moduledoc false
            use AshTypescript.TypedChannel

            typed_channel do
              topic "quiet_secret:*"

              resource QuietNotPublicItem do
                publish(:quiet_secret)
              end
            end
          end

          assert :ok = VerifyTypedChannel.verify(QuietNotPublicChannel.spark_dsl_config())
        end)

      refute warnings =~ "is not marked `public?: true`"
    end
  end

  # Sets an `ash_typescript` warning flag to false for the current test,
  # restoring the original value (or removing it) afterward.
  defp set_flag_false(key) do
    original = Application.get_env(:ash_typescript, key)
    Application.put_env(:ash_typescript, key, false)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:ash_typescript, key)
      else
        Application.put_env(:ash_typescript, key, original)
      end
    end)
  end
end
