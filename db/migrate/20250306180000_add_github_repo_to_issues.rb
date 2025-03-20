class AddGithubRepoToIssues < ActiveRecord::Migration
    def change
      add_column :issues, :github_repo, :string
      add_index :issues, [:github_id, :github_repo], unique: true
      remove_index :issues, :github_id if index_exists?(:issues, :github_id)
    end
  end