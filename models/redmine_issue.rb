class RedmineIssue
  def initialize(data)
    @raw_data = data["payload"] || data
    @issue = @raw_data["issue"]  # Use webhook data, not API
  end

  def id
    @id ||= @issue["id"]
  end

  def title
    @title ||= @issue["subject"]
  end

  def description
    @description ||= @issue["description"]
  end

  def status
    @status ||= @issue["status"]["id"]
  end

  def author
    @author ||= @issue["author"]["name"]
  end

  def assignee
    @assignee ||= @issue["assignee"]  # Hash from webhook (e.g., {"login": "pmercier"})
  end

  def formated_description
    data = "*This issue was generated automatically from Redmine*\n\n" \
           "**Author**: #{author}\n" \
           "**Issue URL**: http://#{ENV['REDMINE_URL']}/issues/#{id}\n\n" \
           "--\n#### Description\n\n#{description}\n\n" \
           "*Comment issue here: #{ENV['REDMINE_URL']}/issues/#{id}*"
    data
  end

  def open?
    @issue["status"]["id"] != 5  # Adjust if "Closed" ID differs
  end
end
