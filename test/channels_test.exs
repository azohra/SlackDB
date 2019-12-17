defmodule SlackDB.ChannelsTest do
  use ExUnit.Case

  import Mox
  import SlackDB.Channels

  @pagination_result_1 %{
    "channels" => [
      %{
        "id" => "CQ5H0JBDZ",
        "name" => "general"
      },
      %{
        "id" => "CQ5H0K15Z",
        "name" => "slackdb"
      }
    ],
    "ok" => true,
    "response_metadata" => %{"next_cursor" => "cursor1"}
  }

  @pagination_result_2 %{
    "channels" => [
      %{
        "id" => "CQ5H0JBDZ",
        "name" => "new"
      }
    ],
    "ok" => true,
    "response_metadata" => %{"next_cursor" => ""}
  }

  @channel_info %{
    id: "CFC6MRQ06",
    name: "slackdb-admin"
  }

  setup do
    Client.Mock
    |> expect(:conversations_list, 6, fn
      _, cursor: nil -> {:ok, @pagination_result_1}
      _, cursor: "cursor1" -> {:ok, @pagination_result_2}
    end)
    |> expect(:conversations_invite, 2, fn
      _, "error_channel", _ -> {:error, %{"ok" => false}}
      _, _, _ -> {:ok, @channel_info}
    end)

    :ok
  end

  test "conversations_list" do
    assert get_all_convos("server") ===
             {:ok,
              [
                %{"id" => "CQ5H0JBDZ", "name" => "general"},
                %{"id" => "CQ5H0K15Z", "name" => "slackdb"},
                %{"id" => "CQ5H0JBDZ", "name" => "new"}
              ]}

    assert get_all_convos("doesnt exist") ===
             {:error, "KeyError: couldn't find key `doesnt exist`"}
  end

  test "invite_to_channel" do
    assert invite_to_channel("server", :supervisor, ["id1"]) ==
             {:ok, %{id: "CFC6MRQ06", name: "slackdb-admin"}}

    assert invite_to_channel("server", "error_channel", ["id1"]) ==
             {:error, %{"ok" => false}}
  end
end
