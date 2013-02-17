class RenameHashColumn < ActiveRecord::Migration
  def self.up
    rename_column :triggers, :hash, :trigger_hash
  end

  def self.down
    rename_column :triggers, :trigger_hash, :hash
  end
end
