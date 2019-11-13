use Mix.Config

config :tesla, adapter: Tesla.Mock

config :slackdb,
  servers: %{
    "server" => %{
      bot_token: "xoxb",
      user_token: "xoxp",
      bot_name: "Jeanie",
      supervisor_channel_name: "slackdb-admin",
      supervisor_channel_id: "CFC6MRQ06"
    },
    "un_initialized_server" => %{
      bot_token: "xoxb",
      user_token: "xoxp",
      bot_name: "Jeanie",
      supervisor_channel_name: "slackdb-new-admins",
      supervisor_channel_id: "CFC6MRQ07"
    }
  }
