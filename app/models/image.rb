class Image < ApplicationRecord

  def self.fetch_all perform_update=true
    Rails.cache.delete "next_cursor"
    Rails.cache.delete "next_cursor_asc"
    self.fetch "desc", perform_update
  end

  def self.fetch order="desc", perform_update=true
    completed = false
    cache_key = "next_cursor#{order == "asc" ? "_asc" : ""}"
    seen_ids = []
    Image.with_network_retry do
      while !completed do
        results = Cloudinary::Api.resources(
          direction: order, 
          tags: true, 
          max_results: 500, 
          next_cursor: Rails.cache.read(cache_key)
        )
        puts results["next_cursor"]
        puts results["resources"].first
        #return
        if results["rate_limit_remaining"] == 0
          while Time.now < results["rate_limit_reset_at"]
            puts "Sleeping #{results.rate_limit_reset_at}"
            sleep 5
          end
        end

        overlap = (results["resources"] & results["resources"].collect {|i| i["public_id"] })
        if(overlap.length > 0)
          raise "Found an existing image #{overlap}"
        end

        Image.store_or_update_results results["resources"], perform_update
        Rails.cache.write cache_key, results["next_cursor"]
        if results["resources"].blank?
          completed = true
        end
        seen_ids = seen_ids + results["resources"].collect {|i| i["public_id"] }
      end
    end
  end

  def self.store_or_update_results results, perform_update=true
    existing_images = Image.where(cloudinary_id: results.collect {|i| i["public_id"] }).to_a
    puts "Got #{existing_images.count} existing images"
    results.each do |result|
      image = existing_images.find {|i| i.cloudinary_id == result["public_id"] }
      if image
        if perform_update
          puts "Updating existing image"
          image.cloudinary_id = result["public_id"]
          image.cloudinary_data = result
          image.width = result["width"]
          image.height = result["height"]
          image.tags = result["tags"]
          image.format = result["format"]
          image.save
        end
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
          Image.with_network_retry do
            Cloudinary::Api.update(image.cloudinary_id, :tags => image.tags + [tag]) unless image.tags.include?(tag)
            puts "tag set for #{image.cloudinary_id}"
          end
        end
      end
    end
  end

  def self.tags_for_images
    Image.set_tag_for_filter({format: "svg", width: 1080, height: 1350}, "insight_circles")
  end

  def delete_from_cloudinary
    Image.with_network_retry do
      result = Cloudinary::Api.delete_resources([self.cloudinary_id])
      if result
        self.deleted_at = Time.now
        self.save
      end
    end
  end

  def self.with_network_retry
    begin
      yield if block_given?
    rescue RestClient::Exceptions::OpenTimeout, RestClient::Exceptions::ReadTimeout, SocketError
      puts "Network error. Waiting and retrying"
      sleep 10
      retry
    rescue Cloudinary::Api::RateLimited => e
      puts "Rate limit hit, sleeping 1 minute"
      sleep 60
      retry
    end
  end

  def self.delete_many_from_cloudinary images, batch_size = 100
    images.in_groups_of(batch_size).each do |group|
      group = group.compact
      #puts group.join(" | ")
      Image.with_network_retry do
        result = Cloudinary::Api.delete_resources(group.collect(&:cloudinary_id))
        puts result
        #sleep(1)
        if result && result["deleted"]
          to_delete = []
          result["deleted"].each do |k,v|
            if v == "deleted" || v == "not_found"
              to_delete << k
            end
          end
          #puts to_delete
          items_to_delete = group.select {|i| to_delete.include?(i.cloudinary_id) }
          #puts items_to_delete
          Image.where(id: items_to_delete.collect(&:id)).update_all(deleted_at: Time.now)
        else
          raise("No result from delete request")
        end
      end
    end
  end

  def self.remove query
    if(!query[:deleted_at])
      query[:deleted_at] = nil
    end
    images = Image.where(query)
    Image.delete_many_from_cloudinary(images)
    true
  end

  def self.widths
    Image.all.group(:width).count
  end

  def self.update_many query
    images = Image.where(query)
    images.in_groups_of(100).each do |group|
      puts "Updating a group of #{group.length}"
      Image.with_network_retry do
        results = Cloudinary::Api.resources_by_ids(group)
        puts results
        Image.store_or_update_results(results)
      end
    end
  end
end
