class GithubIssue
  attr_reader :data

  def initialize(data)
    @data = data
  end

  def id
    @id ||= @data["issue"]["number"]  # Use issue number (e.g., 70), not global ID
  end

  def title
    @title ||= @data["issue"]["title"]
  end

  def description
    @description ||= @data["issue"]["body"]
  end
end
