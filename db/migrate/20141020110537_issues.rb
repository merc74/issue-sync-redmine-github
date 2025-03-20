class Issues < ActiveRecord::Migration
  def change
    execute <<-SQL
      CREATE TABLE issues (
        id INT(11) NOT NULL AUTO_INCREMENT PRIMARY KEY,
        github_id INT(11),
        redmine_id INT(11),
        created_at DATETIME NOT NULL,
        updated_at DATETIME NOT NULL
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    SQL
  end
end
