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
    # The fixture below intentionally fails verification, so it is defined
    # inside the capture closure to keep the `@after_verify` DslError that
    # Elixir's parallel checker echoes out of `mix test` output.
    test "rejects event that does not match any publication" do
      {result, _stderr} =
        ExUnit.CaptureIO.with_io(:standard_error, fn ->
          defmodule ChannelWithMissingEvent do
            use Phoenix.Channel
            use AshTypescript.TypedChannel

            def join(_topic, _payload, socket), do: {:ok, socket}

            typed_channel do
              topic "missing:*"

              resource AshTypescript.Test.ChannelItem do
                publish(:item_created)
                publish(:nonexistent_event)
              end
            end
          end

          VerifyTypedChannel.verify(ChannelWithMissingEvent.spark_dsl_config())
        end)

      assert {:error, %Spark.Error.DslError{message: message}} = result
      assert message =~ "No publication with event :nonexistent_event"
      assert message =~ inspect(AshTypescript.Test.ChannelItem)
    end
  end

  describe "verify_unique_event_names" do
    # Same as above: the channel fixture below fails verification on purpose.
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
            returns: :map,
            transform: fn n -> %{id: n.data.id} end
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          defaults [:create]
        end
      end

      {result, _stderr} =
        ExUnit.CaptureIO.with_io(:standard_error, fn ->
          defmodule ChannelWithDuplicateEvents do
            use Phoenix.Channel
            use AshTypescript.TypedChannel

            def join(_topic, _payload, socket), do: {:ok, socket}

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

          VerifyTypedChannel.verify(ChannelWithDuplicateEvents.spark_dsl_config())
        end)

      assert {:error, %Spark.Error.DslError{message: message}} = result
      assert message =~ "Duplicate event names"
      assert message =~ "item_created"
    end
  end

  describe "verify_object_payloads" do
    # Phoenix only pushes map payloads (`Phoenix.Socket.V2.JSONSerializer`
    # raises otherwise), so a declared publication whose `returns` type is not
    # pushed as a JSON object must be refused at compile time (issue #104).
    # Fixtures that fail on purpose are defined inside the capture closure, as
    # in the tests above.
    defmodule NonMapPayloadItem do
      @moduledoc false
      use Ash.Resource, domain: nil, notifiers: [Ash.Notifier.PubSub]

      pub_sub do
        module AshTypescript.Test.TestEndpoint
        prefix "non_map_payload"

        # The guide's former `post_updated`: a string-typed `:auto` calculation.
        publish :update, [:id], event: "title_changed", public?: true, transform: :title_only

        publish :create, [:id],
          event: "tags_changed",
          public?: true,
          returns: {:array, :string},
          transform: fn _notification -> [] end

        publish :destroy, [:id],
          event: "status_changed",
          public?: true,
          returns: AshTypescript.Test.Todo.Status,
          transform: fn _notification -> :pending end
      end

      attributes do
        uuid_primary_key :id
        attribute :title, :string, public?: true
      end

      calculations do
        calculate :title_only, :auto, expr(title) do
          public? true
        end
      end

      actions do
        defaults [:read, :create, :update, :destroy]
      end
    end

    defp verify_channel_capturing(fun) do
      {result, _stderr} = ExUnit.CaptureIO.with_io(:standard_error, fun)
      result
    end

    test "rejects a publication whose calculation transform returns a string" do
      result =
        verify_channel_capturing(fn ->
          defmodule StringPayloadChannel do
            use Phoenix.Channel
            use AshTypescript.TypedChannel

            def join(_topic, _payload, socket), do: {:ok, socket}

            typed_channel do
              topic "string_payload:*"

              resource NonMapPayloadItem do
                publish(:title_changed)
              end
            end
          end

          VerifyTypedChannel.verify(StringPayloadChannel.spark_dsl_config())
        end)

      assert {:error, %Spark.Error.DslError{message: message, path: path}} = result

      assert message =~
               "Event :title_changed on #{inspect(NonMapPayloadItem)} in typed channel " <>
                 "#{inspect(__MODULE__.StringPayloadChannel)} has payload type " <>
                 "Ash.Type.String, which is not pushed as a JSON object."

      assert message =~ "Phoenix channels can only push map payloads"
      assert message =~ "expr(%{title: title})"
      assert path == [:typed_channel, :resource, :publish, :title_changed]
    end

    test "rejects a publication whose returns type is an array" do
      result =
        verify_channel_capturing(fn ->
          defmodule ArrayPayloadChannel do
            use Phoenix.Channel
            use AshTypescript.TypedChannel

            def join(_topic, _payload, socket), do: {:ok, socket}

            typed_channel do
              topic "array_payload:*"

              resource NonMapPayloadItem do
                publish(:tags_changed)
              end
            end
          end

          VerifyTypedChannel.verify(ArrayPayloadChannel.spark_dsl_config())
        end)

      assert {:error, %Spark.Error.DslError{message: message}} = result
      assert message =~ "Event :tags_changed on #{inspect(NonMapPayloadItem)}"
      assert message =~ "has payload type {:array, Ash.Type.String}"
    end

    test "rejects a publication whose returns type is an enum" do
      result =
        verify_channel_capturing(fn ->
          defmodule EnumPayloadChannel do
            use Phoenix.Channel
            use AshTypescript.TypedChannel

            def join(_topic, _payload, socket), do: {:ok, socket}

            typed_channel do
              topic "enum_payload:*"

              resource NonMapPayloadItem do
                publish(:status_changed)
              end
            end
          end

          VerifyTypedChannel.verify(EnumPayloadChannel.spark_dsl_config())
        end)

      assert {:error, %Spark.Error.DslError{message: message}} = result
      assert message =~ "Event :status_changed on #{inspect(NonMapPayloadItem)}"
      assert message =~ "has payload type AshTypescript.Test.Todo.Status"
    end

    defmodule ObjectPayloadItem do
      @moduledoc false
      use Ash.Resource, domain: nil, notifiers: [Ash.Notifier.PubSub]

      pub_sub do
        module AshTypescript.Test.TestEndpoint
        prefix "object_payload"

        publish :create, [:id],
          event: "as_map",
          public?: true,
          returns: :map,
          constraints: [fields: [id: [type: :uuid]]],
          transform: fn n -> %{id: n.data.id} end

        publish :create, [:id], event: "as_map_calc", public?: true, transform: :title_map

        publish :create, [:id],
          event: "as_embedded",
          public?: true,
          returns: AshTypescript.Test.TodoMetadata,
          transform: fn _n -> nil end

        publish :create, [:id],
          event: "as_resource_struct",
          public?: true,
          returns: :struct,
          constraints: [instance_of: AshTypescript.Test.Todo],
          transform: fn _n -> nil end

        publish :create, [:id],
          event: "as_typed_struct",
          public?: true,
          returns: :struct,
          constraints: [fields: [id: [type: :uuid]]],
          transform: fn _n -> nil end

        publish :create, [:id],
          event: "as_union",
          public?: true,
          returns: :union,
          constraints: [types: [note: [type: :string], count: [type: :integer]]],
          transform: fn _n -> nil end

        publish :create, [:id],
          event: "as_keyword",
          public?: true,
          returns: :keyword,
          constraints: [fields: [id: [type: :uuid]]],
          transform: fn _n -> nil end

        publish :create, [:id],
          event: "as_tuple",
          public?: true,
          returns: :tuple,
          constraints: [fields: [id: [type: :uuid]]],
          transform: fn _n -> nil end

        publish :create, [:id],
          event: "as_map_new_type",
          public?: true,
          returns: AshTypescript.Test.CustomMetadata,
          transform: fn _n -> nil end

        # The shape of a `:term` value is not known, so it is not refused.
        publish :create, [:id],
          event: "as_term",
          public?: true,
          returns: :term,
          transform: fn _n -> nil end

        publish :create, [:id],
          event: "as_union_new_type",
          public?: true,
          returns: AshTypescript.Test.ContentItem,
          transform: fn _n -> nil end
      end

      attributes do
        uuid_primary_key :id
        attribute :title, :string, public?: true
      end

      calculations do
        calculate :title_map, :auto, expr(%{title: title}) do
          public? true
        end
      end

      actions do
        defaults [:read, :create]
      end
    end

    defmodule ObjectPayloadChannel do
      @moduledoc false
      use Phoenix.Channel
      use AshTypescript.TypedChannel

      def join(_topic, _payload, socket), do: {:ok, socket}

      typed_channel do
        topic "object_payload:*"

        resource ObjectPayloadItem do
          publish(:as_map)
          publish(:as_map_calc)
          publish(:as_embedded)
          publish(:as_resource_struct)
          publish(:as_typed_struct)
          publish(:as_union)
          publish(:as_keyword)
          publish(:as_tuple)
          publish(:as_map_new_type)
          publish(:as_union_new_type)
          publish(:as_term)
        end
      end
    end

    test "accepts map, struct, resource, union, keyword, tuple and unknown-shape payloads" do
      assert :ok = VerifyTypedChannel.verify(ObjectPayloadChannel.spark_dsl_config())
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
            use Phoenix.Channel
            use AshTypescript.TypedChannel

            def join(_topic, _payload, socket), do: {:ok, socket}

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
                returns: :map,
                transform: fn n -> %{id: n.data.id} end

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
            use Phoenix.Channel
            use AshTypescript.TypedChannel

            def join(_topic, _payload, socket), do: {:ok, socket}

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
            use Phoenix.Channel
            use AshTypescript.TypedChannel

            def join(_topic, _payload, socket), do: {:ok, socket}

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
                returns: :map,
                transform: fn n -> %{id: n.data.id} end
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
            use Phoenix.Channel
            use AshTypescript.TypedChannel

            def join(_topic, _payload, socket), do: {:ok, socket}

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
