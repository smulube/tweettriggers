require 'digest/sha1'
require 'twitter-text'

class TriggerException < Exception; end

class User < ActiveRecord::Base
  has_many :triggers
end

class Trigger < ActiveRecord::Base
  include Twitter::Validation

  belongs_to :user

  before_validation :generate_hash

  def send_tweet(trigger_json)
    return if self.tweet.nil? # Ensure we have a tweet template

    begin
      trigger = JSON.parse(trigger_json)
      # We currently use the value => value format, but we should change it. this will keep us working, and maintain backward compat.
      Twitter.configure do |config|
        config.consumer_key = $twitter_config[:consumer_key]
        config.consumer_secret = $twitter_config[:consumer_secret]
        config.oauth_token = user.oauth_token
        config.oauth_token_secret = user.oauth_secret
      end

      Twitter.update(tweet_text(trigger))
      $redis.incr TOTAL_JOBS
    rescue Exception => e
      $redis.incr TOTAL_ERRORS
      raise TriggerException, "Error delivering trigger: #{e.inspect}, for trigger: #{trigger_json}"
    end
  end

  private

  def tweet_text(trigger)
    msg = build_raw_message(trigger)

    # calculate the actual length of this message (uses twitter-text to take
    # account of url shortening)
    msg_length = tweet_length(msg, { :short_url_length => ENV["SHORT_URL_LENGTH"] || 22,
                                     :short_url_length_https => ENV["SHORT_URL_LENGTH_HTTPS"] || 23 })

    # This is the timestamp fragment we will append
    timestamp = trigger['timestamp']
    timestamp_msg = " at #{format_time(timestamp)}"

    # permitted length is the difference between max length and the timestamp
    # fragment length
    permitted_length = 140 - timestamp_msg.length

    # truncate the message if longer than we can permit
    if msg_length > permitted_length
      msg = msg[0, permitted_length]
    end

    # append the timestamp
    msg << timestamp_msg

    msg
  end

  def format_time(time)
    Time.parse(time).strftime('%Y-%m-%d %T')
  end

  def build_raw_message(trigger)
    new_value = trigger['triggering_datastream']['value']['current_value'] || trigger['triggering_datastream']['value']['value']
    stream_id = trigger['triggering_datastream']['id']
    feed_id = trigger['environment']['id'].to_s

    return self.tweet.gsub('{value}', new_value).
      gsub('{datastream}', stream_id).
      gsub('{feed}', feed_id).
      gsub('{feed_url}', "https://cosm.com/feeds/#{feed_id}")
  end

  def generate_hash
    self.trigger_hash ||= hash_generator
  end

  def hash_generator
    @hashfunc = Digest::SHA1.new
    @hashfunc.update(Time.now.iso8601(6) + rand(100000000).to_s)
    @hashfunc.hexdigest
  end
end

