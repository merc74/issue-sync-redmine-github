require 'sinatra/activerecord'

configure :development, :production do
  db = URI.parse(ENV['DATABASE_URL'] || 'mysql2://localhost/issue_sync_db')
  ActiveRecord::Base.establish_connection(
    adapter:  db.scheme == 'mysql2' ? 'mysql2' : db.scheme,
    host:     db.host,
    username: db.user,
    password: db.password,
    database: db.path[1..-1],
    encoding: 'utf8mb4'
  )
end
