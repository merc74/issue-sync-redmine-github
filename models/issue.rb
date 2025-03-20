require 'httparty'

class Issue < ActiveRecord::Base
  self.table_name = "issues"
  validates :github_id, uniqueness: { scope: :github_repo }, allow_nil: true
  validates :redmine_id, uniqueness: true, allow_nil: true

  def self.logger=(logger)
    @logger = logger
  end

  def self.logger
    @logger
  end

  def logger
    self.class.logger
  end

  # Mapping of GitHub repo names to Redmine project IDs (numeric)
  REPO_TO_PROJECT_MAP = {
    'livelaps-sites' => 57,
    'livelaps-webapp' => 62,
    'livelaps-app' => 56,
    'livelaps-api' => 60,
    'livelaps-cms' => 59,
    'livelaps-ui' => 61
  }

  def create_on_redmine(github)
    repo_name = github.repository ? github.repository["full_name"].split('/').last : (github_repo || ENV['GITHUB_REPO'])
    project_id = REPO_TO_PROJECT_MAP[repo_name] || 57

    title = github.title || "Untitled GitHub Issue"
    body = github.body || "No description provided"
    number = github.number || self.github_id

    options = {
      :headers => { 
        "X-Redmine-API-Key" => ENV['REDMINE_API_KEY'], 
        "Content-Type" => "application/json",
        "User-Agent" => "Redmine-GitHub-Sync"
      },
      :body => { 
        :issue => { 
          :project_id => project_id,
          :subject => title,
          :description => "#{body}\n\n*Synced from GitHub*\n**Issue URL**: https://github.com/#{ENV['GITHUB_OWNER']}/#{repo_name}/issues/#{number}",
          :tracker_id => 1,  # "Defect"
          :status_id => 1    # "New"
        } 
      }.to_json
    }
    logger.debug "Sending Redmine API request: #{options.inspect}"
    response = HTTParty.post("#{ENV['REDMINE_URL']}/issues.json", options)
    logger.debug "Redmine API response: #{response.code} - #{response.body}"
    if response.success?
      update_attributes!(:redmine_id => response["issue"]["id"], :github_repo => repo_name)
      logger.info "Created Redmine issue ##{response["issue"]["id"]} for GitHub ID #{number} in project #{project_id}"
    else
      logger.error "Failed to create Redmine issue for GitHub ID #{number}: #{response.code} - #{response.body}"
    end
  end

  def create_on_github(redmine)
    user_mapping = {
      'pmercier' => 'merc74',
      'ndelorme' => 'NDelo007',
      'rmercier' => 'RaphMerc007',
      'andrewd' => 'andduq'
    }
  
    redmine_assignee = redmine.assignee && redmine.assignee["login"] ? redmine.assignee["login"] : nil
    github_assignee = redmine_assignee && user_mapping[redmine_assignee] ? user_mapping[redmine_assignee] : 'merc74'
  
    logger.debug "Redmine assignee: #{redmine_assignee}, Mapped GitHub assignee: #{github_assignee}"
  
    project_to_repo_map = REPO_TO_PROJECT_MAP.invert
    repo_name = github_repo || project_to_repo_map[redmine.project["id"]] || ENV['GITHUB_REPO']
  
    options = {
      :headers => { 
        "Authorization" => "token #{ENV['GITHUB_API_KEY']}", 
        "Accept" => "application/vnd.github.v3+json",
        "User-Agent" => "Redmine-GitHub-Sync"
      },
      :body => { 
        :title => redmine.subject, 
        :body => "#{redmine.description}\n\n*Synced from Redmine*\n**Issue URL**: https://redmine.softguard.ca/issues/#{redmine.id}",
        :assignees => github_assignee ? [github_assignee] : []
      }.to_json
    }
    logger.debug "Sending GitHub API request to repo #{repo_name}: #{options.inspect}"
    response = HTTParty.post("https://api.github.com/repos/#{ENV['GITHUB_OWNER']}/#{repo_name}/issues", options)
    logger.debug "GitHub API response: #{response.code} - #{response.body}"
    if response.success?
      update_attributes!(:github_id => response["number"], :github_repo => repo_name)
      logger.info "Created GitHub issue ##{response["number"]} for Redmine ID #{redmine.id} assigned to #{github_assignee || 'none'} in repo #{repo_name}"
    else
      logger.error "Failed to create GitHub issue for Redmine ID #{redmine.id}: #{response.code} - #{response.body}"
    end
  end

  def update_on_redmine(github)
    return unless redmine_id
    options = {
      :headers => { 
        "X-Redmine-API-Key" => ENV['REDMINE_API_KEY'], 
        "Content-Type" => "application/json",
        "User-Agent" => "Redmine-GitHub-Sync"
      },
      :body => { 
        :issue => { 
          :subject => github.title, 
          :description => github.body || "*Synced from GitHub*"
        } 
      }.to_json
    }
    logger.debug "Sending Redmine update request: #{options.inspect}"
    response = HTTParty.put("#{ENV['REDMINE_URL']}/issues/#{redmine_id}.json", options)
    logger.debug "Redmine update response: #{response.code} - #{response.body}"
    if response.success?
      logger.info "Updated Redmine issue ##{redmine_id} with title '#{github.title}'"
    else
      logger.error "Failed to update Redmine issue ##{redmine_id}: #{response.code} - #{response.body}"
    end
  end

  def transfer_on_github(new_project_id)
    return unless github_id && github_repo
    logger.debug "Starting transfer for GitHub ID #{github_id} from repo #{github_repo}"
    
    project_to_repo_map = REPO_TO_PROJECT_MAP.invert
    new_project_id_int = new_project_id.to_i
    new_repo_name = project_to_repo_map[new_project_id_int] || ENV['GITHUB_REPO']
    
    logger.debug "Mapped new_project_id #{new_project_id_int} to repo #{new_repo_name}"
    return if new_repo_name == github_repo # No transfer needed if repo hasn't changed

    options = {
      :headers => { 
        "Authorization" => "token #{ENV['GITHUB_API_KEY']}", 
        "Accept" => "application/vnd.github.v3+json",
        "User-Agent" => "Redmine-GitHub-Sync"
      },
      :body => { 
        "new_repository" => new_repo_name # Just the repo name, not full path
      }.to_json
    }
    transfer_url = "https://api.github.com/repos/#{ENV['GITHUB_OWNER']}/#{github_repo}/issues/#{github_id}/transfer"
    logger.debug "Transferring GitHub issue ##{github_id} from #{github_repo} to #{new_repo_name} via #{transfer_url}: #{options.inspect}"
    begin
      response = HTTParty.post(transfer_url, options)
      logger.debug "GitHub transfer response: #{response.code} - #{response.body}"
      if response.code == 201
        update_attributes!(:github_repo => new_repo_name)
        logger.info "Transferred GitHub issue ##{github_id} to repo #{new_repo_name} for Redmine ID #{redmine_id}"
      else
        logger.error "Failed to transfer GitHub issue ##{github_id} to #{new_repo_name}: #{response.code} - #{response.body}"
        # Log token scope check for debugging
        token_check = HTTParty.get("https://api.github.com/user", :headers => options[:headers])
        logger.debug "Token scope check: #{token_check.code} - #{token_check.headers['x-oauth-scopes']}"
      end
    rescue => e
      logger.error "Error during GitHub transfer for issue ##{github_id}: #{e.message}\n#{e.backtrace.join("\n")}"
    end
  end
end