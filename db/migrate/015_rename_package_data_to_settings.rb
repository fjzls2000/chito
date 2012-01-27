class RenamePackageDataToSettings < ActiveRecord::Migration
  def up
    rename_column :articles, :package_data, :settings
    rename_column :groups,   :package_data, :settings
    rename_column :users,    :package_data, :settings
  end

  def down
    rename_column :articles, :settings, :package_data
    rename_column :groups,   :settings, :package_data
    rename_column :users,    :settings, :package_data
  end
end
