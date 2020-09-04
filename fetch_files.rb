# frozen_string_literal: true

require 'httparty'
require 'awesome_print'
require 'ruby-progressbar'
require 'logger'
require 'yaml'

log = Logger.new("./#{DateTime.now}.log")

config = YAML.load_file('config.yml')
token = config[:token]
base_url = config[:base_url]

offset = 0

loop do
  # Get List of Assets
  response = HTTParty.get("#{base_url}assets.json",
                          headers: { 'Authorization' => "Bearer #{token}" },
                          query: { 'offset' => offset, 'limit' => 1000 })
  if response.code != 200
    log.error("Error in list call: #{response.code}")
    break
  end

  items = response['response']['items']

  break if items.empty?

  progressbar = ProgressBar.create(title: 'Items', starting_at: 0, total: items.length, format: '%a %e %P% Processed: %c from %C')

  items.each do |item|
    progressbar.increment

    # Skip if not a doc

    unless %w[document photo video].include?(item['filetype'])
      log.info("Not a document:  #{item['id']} - #{item['name']} - #{item['filetype']}")
      next

    end

    # Skip if we have the file

    unless Dir.glob("./files/#{item['name']}").empty?
      log.info("File already exists for #{item['id']} - #{item['name']}")
      next

    end

    # Get Item Details

    get_response = HTTParty.get("#{base_url}assets/#{item['id']}.json",
                                headers: { 'Authorization' => "Bearer #{token}" })
    if get_response.code != 200
      log.error("Response: #{get_response.code} from item: #{item['id']}")
      next

    end
    item_details = get_response['response']

    unless item_details['isDownloadable']
      unlock_response = HTTParty.post("#{base_url}assets/#{item['id']}.json",
                                      headers: { 'Authorization' => "Bearer #{token}" },
                                      body: { 'isDownloadable' => true })

      if unlock_response.code != 200
        log.error("Error trying to unlock item #{item['id']} - Response Code: #{unlock_response.code}")
        next

      end
    end

    getlink_response = HTTParty.get("#{base_url}assets/#{item['id']}.json",
                                    headers: { 'Authorization' => "Bearer #{token}" })
    if getlink_response.code != 200
      log.error "Error trying to get link for item: #{item['id']} - Response: #{getlink_response.code}}"
      next

    end

    dl_link = getlink_response['response']['shortLivedDownloadLink']
    dl_name = getlink_response['response']['name']

    if dl_link.nil? || dl_name.nil?
      log.warn("No name or download link for item #{item['id']} - Name: #{dl_name} Link: #{dl_link}")
      next
    end

    File.open("./files/#{dl_name}", 'w') do |file|
      file.binmode
      HTTParty.get(dl_link, stream_body: true) do |fragment|
        file.write(fragment)
      end
    end
    log.info("Downloaded item #{item['id']}, #{dl_name}")

    next if item_details['isDownloadable']

    ndl_response = HTTParty.post("#{base_url}assets/#{item['id']}.json",
                                 headers: { 'Authorization' => "Bearer #{token}" },
                                 body: { 'isDownloadable' => false })

    next unless ndl_response.code != 200

    log.error("Error trying to unlock item #{item['id']} - Response Code: #{ndl_response.code}")
  end
  offset += items.length
end
