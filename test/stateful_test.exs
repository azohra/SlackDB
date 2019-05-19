defmodule StatefulTest do
  use ExUnit.Case, async: false
  import Tesla.Mock
  import SlackDB

  @s_url "https://slack.com/api"

  setup_all do
    mock_global(fn
      %{
        method: :post,
        url: "#{@s_url}/search.messages",
        body: "highlight=false&query=in%3A%23general+%22key%22&sort=timestamp&sort_dir=desc"
      } ->
        %Tesla.Env{
          status: 200,
          body:
            "{\"messages\":{\"matches\":[{\"channel\":{\"id\":\"CFFD4EEMR\",\"name\":\"general\"},\"text\":\"key :monkey:\",\"ts\":\"1555913457.017900\"}],\"total\":1},\"ok\":true,\"query\":\"in:#general \\\"key\\\"\"}"
        }

      %{
        method: :post,
        url: "#{@s_url}/search.messages",
        body:
          "highlight=false&query=in%3A%23sladckdb-admin+from%3AJeanie+%22server%22&sort=timestamp&sort_dir=desc"
      } ->
        %Tesla.Env{
          status: 200,
          body:
            "{\"messages\":{\"matches\":[{\"channel\":{\"id\":\"CFC6MRQ06\",\"name\":\"sladckdb-admin\"},\"text\":\"server :monkey:\",\"ts\":\"1555913457.017900\"}],\"total\":1},\"ok\":true,\"query\":\"in:#sladckdb-admin from:@Jeanie\\\"server\\\"\"}"
        }

      %{
        method: :post,
        url: "#{@s_url}/search.messages",
        body:
          "highlight=false&query=in%3A%23sladckdb-new-admins+from%3AJeanie+%22un_initialized_server%22&sort=timestamp&sort_dir=desc"
      } ->
        %Tesla.Env{
          status: 200,
          body:
            "{\"messages\":{\"matches\":[],\"total\":0},\"ok\":true,\"query\":\"in:#sladckdb-new-admins from:@Jeanie\\\"un_initialized_server\\\"\"}"
        }

      %{
        method: :post,
        url: "#{@s_url}/conversations.replies",
        body: "channel=CFC6MRQ06&cursor=&limit=1&ts=1555913457.017900"
      } ->
        %Tesla.Env{
          status: 200,
          body:
            "{\"has_more\":false,\"messages\":[{\"key_at_top_of_thread\":\"fake\"},{\"text\":\"{\\\"random\\\":\\\"random_id\\\"}\",\"ts\":\"1555913463.018000\"}],\"ok\":true}"
        }

      %{
        method: :post,
        url: "#{@s_url}/chat.postMessage"
      } ->
        %Tesla.Env{
          status: 200,
          body:
            "{\"channel\":\"CFC6MRQ06\",\"message\":{\"text\":\"value\",\"thread_ts\":\"1556164115.000100\",\"ts\":\"1556164115.000200\"},\"ok\":true,\"ts\":\"1556164115.000200\"}"
        }

      %{
        method: :post,
        url: "#{@s_url}/conversations.invite"
      } ->
        %Tesla.Env{
          status: 200,
          body: "{\"channel\":{\"id\":\"C012AB3CD\",\"name\":\"general\"},\"ok\":true}"
        }

      %{
        method: :post,
        url: "#{@s_url}/conversations.archive"
      } ->
        %Tesla.Env{status: 200, body: "{\"ok\":true}"}

      %{
        method: :post,
        url: "#{@s_url}/conversations.create"
      } ->
        %Tesla.Env{
          status: 200,
          body: "{\"channel\":{\"id\":\"C012AB3CD\",\"name\":\"new_channel\"},\"ok\":true}"
        }

      %{
        method: :post,
        url: "#{@s_url}/conversations.list",
        # limit value in the body is spoofed. the actual response is from when limit=2
        body: "cursor=&exclude_archived=true&limit=200&types=public_channel%2Cprivate_channel"
      } ->
        %Tesla.Env{
          status: 200,
          body:
            "{\"channels\":[{\"id\":\"CFAQ7UA02\",\"name\":\"iris\"},{\"id\":\"CFBRT13C7\",\"name\":\"general\"}],\"ok\":true,\"response_metadata\":{\"next_cursor\":\"dGVhbTpDRkM2TVJRMDY=\"}}"
        }

      %{
        method: :post,
        url: "#{@s_url}/conversations.list",
        # limit value in the body is spoofed. the actual response is from when limit=2
        body:
          "cursor=dGVhbTpDRkM2TVJRMDY%3D&exclude_archived=true&limit=200&types=public_channel%2Cprivate_channel"
      } ->
        %Tesla.Env{
          status: 200,
          body:
            "{\"channels\":[{\"id\":\"include_id\",\"name\":\"include\"}],\"ok\":true,\"response_metadata\":{\"next_cursor\":\"\"}}"
        }

      %{
        method: :post,
        url: "#{@s_url}/chat.delete"
      } ->
        %Tesla.Env{
          status: 200,
          body: "{\"channel\":\"CHU427918\",\"ok\":true,\"ts\":\"1556164115.000200\"}"
        }

      %{
        method: :post,
        url: "#{@s_url}/conversations.replies",
        # limit value in the body is spoofed. the actual response is from when limit=3
        body: "channel=CFFD4EEMR&cursor=&limit=200&ts=1555913457.017900"
      } ->
        %Tesla.Env{
          status: 200,
          body:
            "{\"has_more\":true,\"messages\":[{\"key_at_top_of_thread\":\"fake\"},{\"text\":\"3\",\"ts\":\"1555913464.018400\"},{\"reactions\":[{\"count\":1,\"name\":\"four\",\"users\":[\"UFAM5HN5R\"]},{\"count\":1,\"name\":\"1234\",\"users\":[\"UFAM5HN5R\"]},{\"count\":1,\"name\":\"clock4\",\"users\":[\"UFAM5HN5R\"]}],\"text\":\"4\",\"ts\":\"1555913465.018600\"},{\"text\":\"5\",\"ts\":\"1555913465.018800\"}],\"ok\":true,\"response_metadata\":{\"next_cursor\":\"bmV4dF90czoxNTU1OTEzNDY0MDE4MjAw\"}}"
        }

      %{
        method: :post,
        url: "#{@s_url}/conversations.replies",
        # limit value in the body is spoofed. the actual response is from when limit=3
        body:
          "channel=CFFD4EEMR&cursor=bmV4dF90czoxNTU1OTEzNDY0MDE4MjAw&limit=200&ts=1555913457.017900"
      } ->
        %Tesla.Env{
          status: 200,
          body:
            "{\"has_more\":false,\"messages\":[{\"key_at_top_of_thread\":\"fake\"},{\"text\":\"1\",\"ts\":\"1555913463.018000\"},{\"client_msg_id\":\"b8e55066-bb85-4734-bdae-d3f2ab8f4dd7\",\"parent_user_id\":\"UFAM5HN5R\",\"reactions\":[{\"count\":4}],\"text\":\"2\",\"ts\":\"1555913464.018200\"}],\"ok\":true}"
        }
    end)

    :ok
  end

  test "start_link" do
    {:ok, _pid} = SlackDB.start_link()

    assert dump() === %{
             "server" => %{
               bot_token: "xoxb",
               user_token: "xoxp",
               bot_name: "Jeanie",
               supervisor_channel_name: "sladckdb-admin",
               supervisor_channel_id: "CFC6MRQ06",
               channels: %{"random" => "random_id"}
             },
             "un_initialized_server" => %{
               bot_token: "xoxb",
               user_token: "xoxp",
               bot_name: "Jeanie",
               supervisor_channel_name: "sladckdb-new-admins",
               supervisor_channel_id: "CFC6MRQ07",
               channels: %{}
             }
           }
  end

  test "create" do
    {:ok, _pid} = SlackDB.start_link()

    assert create("server", "not_in_state", "key_phrase", "value", :single_back) ===
             {:error, "channel_name_not_in_database"}

    assert create("server", "random", "key_phrase", "value", :single_back) === [
             ok: %{
               "channel" => "CFC6MRQ06",
               "message" => %{
                 "text" => "value",
                 "thread_ts" => "1556164115.000100",
                 "ts" => "1556164115.000200"
               },
               "ok" => true,
               "ts" => "1556164115.000200"
             }
           ]
  end

  test "invite_to_channel" do
    {:ok, _pid} = SlackDB.start_link()

    assert invite_to_channel("server", "not_in_state", "user_id") ===
             {:error, "channel_name_not_in_database"}

    assert(
      invite_to_channel("server", "random", "user_id") ===
        {:ok, %{"id" => "C012AB3CD", "name" => "general"}}
    )
  end

  test "archive_channel" do
    {:ok, _pid} = SlackDB.start_link()

    assert archive_channel("server", "random") ===
             {:ok,
              %{
                "server" => %{
                  bot_token: "xoxb",
                  user_token: "xoxp",
                  bot_name: "Jeanie",
                  supervisor_channel_name: "sladckdb-admin",
                  supervisor_channel_id: "CFC6MRQ06",
                  channels: %{}
                },
                "un_initialized_server" => %{
                  bot_token: "xoxb",
                  user_token: "xoxp",
                  bot_name: "Jeanie",
                  supervisor_channel_name: "sladckdb-new-admins",
                  supervisor_channel_id: "CFC6MRQ07",
                  channels: %{}
                }
              }}
  end

  test "new_channel" do
    {:ok, _pid} = SlackDB.start_link()

    assert new_channel("server", "new_channel", false) ===
             {:ok,
              %{
                "server" => %{
                  bot_name: "Jeanie",
                  bot_token: "xoxb",
                  channels: %{"new_channel" => "C012AB3CD", "random" => "random_id"},
                  supervisor_channel_id: "CFC6MRQ06",
                  supervisor_channel_name: "sladckdb-admin",
                  user_token: "xoxp"
                },
                "un_initialized_server" => %{
                  bot_name: "Jeanie",
                  bot_token: "xoxb",
                  channels: %{},
                  supervisor_channel_id: "CFC6MRQ07",
                  supervisor_channel_name: "sladckdb-new-admins",
                  user_token: "xoxp"
                }
              }}
  end

  test "include_channel" do
    {:ok, _pid} = SlackDB.start_link()

    assert include_channel("server", "include") ===
             {:ok,
              %{
                "server" => %{
                  bot_name: "Jeanie",
                  bot_token: "xoxb",
                  channels: %{"include" => "include_id", "random" => "random_id"},
                  supervisor_channel_id: "CFC6MRQ06",
                  supervisor_channel_name: "sladckdb-admin",
                  user_token: "xoxp"
                },
                "un_initialized_server" => %{
                  bot_name: "Jeanie",
                  bot_token: "xoxb",
                  channels: %{},
                  supervisor_channel_id: "CFC6MRQ07",
                  supervisor_channel_name: "sladckdb-new-admins",
                  user_token: "xoxp"
                }
              }}
  end

  ####################################################################################
  ## the following aren't stateful but they are concurrent (need global mocks)########
  ####################################################################################

  test "wipe_thread and delete" do
    ans = [
      ok: %{"channel" => "CHU427918", "ok" => true, "ts" => "1556164115.000200"},
      ok: %{"channel" => "CHU427918", "ok" => true, "ts" => "1556164115.000200"},
      ok: %{"channel" => "CHU427918", "ok" => true, "ts" => "1556164115.000200"},
      ok: %{"channel" => "CHU427918", "ok" => true, "ts" => "1556164115.000200"},
      ok: %{"channel" => "CHU427918", "ok" => true, "ts" => "1556164115.000200"},
      ok: %{"channel" => "CHU427918", "ok" => true, "ts" => "1556164115.000200"}
    ]

    # deletes 6 because conversations.replies is mocked to output a thread of 5 messages (and also deletes key)
    assert SlackDB.Utils.wipe_thread(
             "xoxp",
             %SlackDB.Key{
               channel_id: "CFFD4EEMR",
               channel_name: "general",
               key_phrase: "key",
               metadata: [:single_back],
               server_name: "server",
               ts: "1555913457.017900"
             },
             true
           ) === ans

    # deletes 5 because conversations.replies is mocked to output a thread of 5 messages (doesnt delete key this time)
    assert SlackDB.Utils.wipe_thread(
             "xoxp",
             %SlackDB.Key{
               channel_id: "CFFD4EEMR",
               channel_name: "general",
               key_phrase: "key",
               metadata: [:single_back],
               server_name: "server",
               ts: "1555913457.017900"
             },
             false
           ) === ans |> Enum.take(5)

    # deletes all 5 replies and the key
    assert SlackDB.delete("server", "general", "key") === ans
  end

  test "update" do
    assert update("server", "general", "key", "value") === [
             ok: %{
               "channel" => "CFC6MRQ06",
               "message" => %{
                 "text" => "value",
                 "thread_ts" => "1556164115.000100",
                 "ts" => "1556164115.000200"
               },
               "ok" => true,
               "ts" => "1556164115.000200"
             }
           ]
  end
end
