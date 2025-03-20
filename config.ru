File.open('/var/log/apache2/error.log', 'a') { |f| f.puts "Full config.ru loaded" }
require './app'
run SyncApp
