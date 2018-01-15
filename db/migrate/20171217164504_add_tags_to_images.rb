class AddTagsToImages < ActiveRecord::Migration[5.1]
  def change
    add_column :images, :tags, :string, array: true
  end
end
