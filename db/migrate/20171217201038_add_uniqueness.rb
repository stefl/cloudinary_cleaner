class AddUniqueness < ActiveRecord::Migration[5.1]
  def change
    add_index :images, :cloudinary_id, :unique => true
  end
end
