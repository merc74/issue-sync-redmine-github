require 'dotenv'
Dotenv.load
require 'sinatra/base'
require 'json'
require 'logger'
require 'active_record'
require 'mysql2'
require 'httparty'
require 'ostruct'
require './models/issue'

# Initialize database connection
db = URI.parse(ENV['DATABASE_URL'] || 'mysql2://localhost/issue_sync_db')
ActiveRecord::Base.establish_connection(
  :adapter  => db.scheme == 'mysql2' ? 'mysql2' : db.scheme,
  :host     => db.host,
  :username => db.user || ENV['DATABASE_USERNAME'],
  :password => db.password || ENV['DATABASE_PASSWORD'],
  :database => db.path[1..-1],
  :encoding => 'utf8mb4'
)

# Set up logging
log_file = File.open(File.join(File.dirname(__FILE__), 'log', "#{ENV['RACK_ENV'] || 'development'}.log"), 'a+')
log_file.sync = true
$logger = Logger.new(log_file)
$logger.level = Logger::DEBUG
Issue.logger = $logger

class SyncApp < Sinatra::Base
  configure do
    set :logger, $logger
    disable :logging
  end

  post '/github_hook' do
    request.body.rewind
    body = request.body.read.strip
    begin
      data = JSON.parse(body)
      $logger.debug "GitHub webhook payload: #{data.inspect}"
      unless data["issue"]
        $logger.debug "No issue in payload, skipping"
        return "OK"
      end

      github_id = data["issue"]["number"]
      repo_name = data["repository"]["full_name"].split('/').last
      action = data["action"]
      issue_body = data["issue"]["body"] || ""

      if issue_body.include?("Synced from Redmine") && action != "edited"
        return "OK"
      end

      issue = Issue.where(:github_id => github_id, :github_repo => repo_name).first
      if issue
        if (action == "created" || action == "opened") && !issue.redmine_id
          issue.create_on_redmine(OpenStruct.new(data["issue"].merge("repository" => data["repository"])))
        elsif action == "edited" && issue.redmine_id
          issue.update_on_redmine(OpenStruct.new(data["issue"]))
        end
      else
        if action == "created" || action == "opened"
          issue = Issue.create(:github_id => github_id, :github_repo => repo_name)
          issue.create_on_redmine(OpenStruct.new(data["issue"].merge("repository" => data["repository"])))
        end
      end
    rescue => e
      $logger.error "Error in github_hook: #{e.message}\n#{e.backtrace.join("\n")}"
      status 500
    end
    "OK"
  end

  post '/redmine_hook' do
    request.body.rewind
    body = request.body.read.strip
    begin
      data = JSON.parse(body)
      redmine_id = data["payload"]["issue"]["id"]
      action = data["payload"]["action"]
      issue_body = data["payload"]["issue"]["description"] || ""

      if issue_body.include?("Synced from GitHub") && action != "updated"
        return "OK"
      end

      issue = Issue.where(:redmine_id => redmine_id).first
      if issue
        if (action == "created" || action == "opened") && !issue.github_id
          issue.create_on_github(OpenStruct.new(data["payload"]["issue"]))
        elsif action == "updated" && issue.github_id
          user_mapping = {
            'pmercier' => 'merc74',
            'ndelorme' => 'NDelo007',
            'rmercier' => 'RaphMerc007',
            'andrewd' => 'andduq'
          }
          redmine_assignee = data["payload"]["issue"]["assignee"] && data["payload"]["issue"]["assignee"]["login"]
          github_assignee = redmine_assignee && user_mapping[redmine_assignee] ? user_mapping[redmine_assignee] : nil

          journals = data["payload"]["journal"]
          journals = [journals] if journals.is_a?(Hash)
          if journals
            journals.each do |journal|
              project_change = journal["details"].find { |d| d["prop_key"] == "project_id" }
              if project_change
                old_project_id = project_change["old_value"].to_i
                new_project_id = project_change["value"].to_i
                $logger.debug "Project change detected: #{old_project_id} -> #{new_project_id}"
                issue.transfer_on_github(new_project_id)
                break
              end
            end
          end

          repo_name = issue.github_repo || ENV['GITHUB_REPO']
          response = HTTParty.patch(
            "https://api.github.com/repos/#{ENV['GITHUB_OWNER']}/#{repo_name}/issues/#{issue.github_id}",
            :body => {
              :title => data["payload"]["issue"]["subject"],
              :body => data["payload"]["issue"]["description"],
              :assignees => github_assignee ? [github_assignee] : []
            }.to_json,
            :headers => {
              "Authorization" => "token #{ENV['GITHUB_API_KEY']}",
              "Content-Type" => "application/json",
              "Accept" => "application/vnd.github.v3+json",
              "User-Agent" => "Redmine-GitHub-Sync"
            }
          )
          if response.success?
            $logger.info "Updated GitHub issue ##{issue.github_id} in #{repo_name}"
          else
            $logger.error "Failed to update GitHub issue #{issue.github_id}: #{response.code} - #{response.body}"
          end
        end
      else
        if action == "created" || action == "opened"
          issue = Issue.create(:redmine_id => redmine_id)
          issue.create_on_github(OpenStruct.new(data["payload"]["issue"]))
        end
      end
    rescue => e
      $logger.error "Error in redmine_hook: #{e.message}\n#{e.backtrace.join("\n")}"
      status 500
    end
    "OK"
  end

  get '/*' do
    "Not Found"
  end

  post '/*' do
    "Not Found"
  end

  run! if app_file == $0
end