use Mix.Config

config :slackdb,
  servers: %{
    "test" => %{
      bot_token: "xoxb-835259643318-832594188516-1NotICaPHgqWWqKeFQNXLILJ",
      user_token: "xoxp-835259643318-835259644854-835266928358-7592a2af146ab85209e5882d1665866f",
      bot_name: "slackdbot",
      supervisor_channel_name: "slackdb-admin",
      supervisor_channel_id: "GQ9AK5KK3"
    },
    "test1" => %{
      bot_token: "xoxb-835259643318-832594188516-1NotICaPHgqWWqKeFQNXLILJ",
      user_token: "xoxp-835259643318-835259644854-835266928358-7592a2af146ab85209e5882d1665866f",
      bot_name: "slackdbot",
      supervisor_channel_name: "slackdb-admin",
      supervisor_channel_id: "GQ9AK5KK3"
    }
  }
