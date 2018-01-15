class CreateImages < ActiveRecord::Migration[5.1]
  def change
    create_table :images do |t|
      t.string :cloudinary_id
      t.datetime :deleted_at
      t.boolean :to_delete
      t.jsonb :cloudinary_data

      t.timestamps
    end
  end
end
