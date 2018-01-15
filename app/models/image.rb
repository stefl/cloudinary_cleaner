class Image < ApplicationRecord

  def self.fetch_all
    Rails.cache.delete "next_cursor"
    self.fetch 
  end

  def self.fetch order="desc"
    completed = false
    cache_key = "next_cursor#{order == "asc" ? "_asc" : ""}"
    begin
      while !completed do
        results = Cloudinary::Api.resources(order: order, tags: true, max_results: 500, next_cursor: Rails.cache.read(cache_key))
        #puts results
        #return
        if results["rate_limit_remaining"] == 0
          while Time.now < results["rate_limit_reset_at"]
            puts "Sleeping #{results.rate_limit_reset_at}"
            sleep 5
          end
        end

        Image.store_or_update_results results["resources"]
        Rails.cache.write cache_key, results["next_cursor"]
        if results["resources"].blank?
          completed = true
        end
      end
    rescue Exception => e
      puts results
      raise e
    end
  end

  def self.store_or_update_results results
    existing_images = Image.where(cloudinary_id: results.collect {|i| i["public_id"] }).to_a
    puts "Got #{existing_images.count} existing images"
    results.each do |result|
      image = existing_images.find {|i| i.cloudinary_id == result["public_id"] }
      if image
        puts "Updating existing image"
        image.cloudinary_id = result["public_id"]
        image.cloudinary_data = result
        image.width = result["width"]
        image.height = result["height"]
        image.tags = result["tags"]
        image.format = result["format"]
        image.save
      else
        image = Image.create(cloudinary_id: result["public_id"], cloudinary_data: result, width: result["width"], height: result["height"], tags: result["tags"], format: result["format"] )
      end
      #puts image
    end
  end

  def self.set_tag_for_filter filter, tag
    Image.where(filter).in_groups_of(100).each do |group|
      group.each do |image|
        unless image.cloudinary_id.blank?
          Cloudinary::Api.update(image.cloudinary_id, :tags => image.tags + [tag]) unless image.tags.include?(tag)
          puts "tag set for #{image.cloudinary_id}"
        end
      end
    end
  end

  def self.tags_for_images
    Image.set_tag_for_filter({format: "svg", width: 1080, height: 1350}, "insight_circles")
  end

  def delete_from_cloudinary
    result = Cloudinary::Api.delete_resources([self.cloudinary_id])
    if result
      self.deleted_at = Time.now
      self.save
    end
  end
end
