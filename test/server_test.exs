defmodule SlackDB.ServerTest do
  use ExUnit.Case, async: false

  import Mox
  import SlackDB.Server

  @channel_info %{
    id: "C012AB3CD",
    name: "general"
  }

  setup :set_mox_global

  setup do
    SlackDB.Mock
    |> expect(:read, 2, fn
      "server", _, _, _ ->
        {:ok, "{\"new\":\"CQGTEPMUL\",\"new_private\":\"GQHDCMB9N\"}"}

      "un_initialized_server", _, _, _ ->
        {:error, "found_no_matches"}
    end)

    Messages.Mock
    |> expect(:post_key_val, 1, fn
      _, _, _, _, _ -> {:ok, [ok: %{"ok" => true}]}
    end)

    Client.Mock
    |> expect(:conversations_archive, 2, fn
      _, "channel_works" -> {:ok, %{"ok" => true}}
      _, "channel_fails" -> {:error, "channel_failed"}
    end)

    Channels.Mock
    |> expect(:invite_to_channel, 1, fn
      _, _, _ -> {:ok, @channel_info}
    end)

    :ok
  end

  test "init fails on config" do
    improper_config = %{
      "empty" => %{},
      "working" => %{
        bot_token: "xoxb",
        user_token: "xoxp",
        bot_name: "Jeanie",
        supervisor_channel_name: "slackdb-admin",
        supervisor_channel_id: "CFC6MRQ06"
      },
      "missing" => %{
        bot_token: "xoxb"
      }
    }

    assert init(improper_config) ==
             {:stop, "The following servers are improperly configured: empty, missing"}
  end

  test "start_link and dump" do
    {:ok, _pid} = start_link()

    assert SlackDB.dump() == %{
             "server" => %{
               bot_name: "Jeanie",
               bot_token: "xoxb",
               channels: %{"new" => "CQGTEPMUL", "new_private" => "GQHDCMB9N"},
               supervisor_channel_id: "CFC6MRQ06",
               supervisor_channel_name: "slackdb-admin",
               user_token: "xoxp"
             },
             "un_initialized_server" => %{
               bot_name: "Jeanie",
               bot_token: "xoxb",
               channels: %{},
               supervisor_channel_id: "CFC6MRQ07",
               supervisor_channel_name: "slackdb-new-admins",
               user_token: "xoxp"
             }
           }
  end

  test "handle_call put_channel" do
    state = %{"server" => %{channels: %{}}}
    new_state = %{"server" => %{channels: %{"new_channel" => "new_id"}}}

    assert handle_call({:put_channel, "server", "new_channel", "new_id"}, nil, state) ==
             {:reply, {:ok, new_state}, new_state}
  end

  test "handle_call archive" do
    state = %{
      "server" => %{
        user_token: "xoxp",
        channels: %{"channel_works" => "channel_works", "channel_fails" => "channel_fails"}
      }
    }

    assert handle_call({:archive, "server", "channel_works"}, nil, state) ==
             {:reply, {:ok, %{"ok" => true}},
              %{
                "server" => %{channels: %{"channel_fails" => "channel_fails"}, user_token: "xoxp"}
              }}

    assert handle_call({:archive, "server", "channel_fails"}, nil, state) ==
             {:reply, {:error, "channel_failed"}, state}

    assert handle_call({:archive, "server", "channel_doesnt_exist"}, nil, state) ==
             {:reply, {:error, "channel_name_not_in_database"}, state}
  end

  test "handle_call invite" do
    state = %{"server" => %{user_token: "xoxp", channels: %{"channel_works" => "channel_works"}}}

    assert handle_call({:invite, "server", "channel_works", ["id1", "id2"]}, nil, state) ==
             {:reply, {:ok, @channel_info}, state}
  end

  test "handle_call create" do
    state = %{"server" => %{user_token: "xoxp", channels: %{"channel_works" => "channel_works"}}}

    assert handle_call(
             {:create, "server", "channel_works", "key_phrase", "values", [:single_back]},
             nil,
             state
           ) == {:reply, {:ok, [ok: %{"ok" => true}]}, state}
  end
end
