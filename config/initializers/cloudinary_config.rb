puts ENV["CLOUDINARY_URL"]
uri = URI.parse(ENV["CLOUDINARY_URL"])

Cloudinary.config do |config|
  config.cloud_name = uri.host
  config.api_key = uri.user
  config.api_secret = uri.password
  config.cdn_subdomain = true
end