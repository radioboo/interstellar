require 'rest-client'
require 'json'
require 'date'
require 'csv'
require 'yaml'
require 'pry'

CONFIG = YAML.load_file('./secrets/secrets.yml')
SENTINEL_DATE_TXT = 'sentinel_date.txt'

class Slack
  def self.notify(message)
    RestClient.post CONFIG["slack_url"], {
      payload:
      { text: message }.to_json
    },
    content_type: :json,
    accept: :json
  end
end

class Review
  attr_accessor :version
  attr_accessor :device
  attr_accessor :submitted_at
  attr_accessor :rate
  attr_accessor :title
  attr_accessor :text
  attr_accessor :link

  def initialize data = {}
    @version      = data[:version] ? data[:version].to_s.encode("utf-8") : nil
    @device       = data[:device] ? data[:device].to_s.encode("utf-8") : nil
    @submitted_at = DateTime.parse(data[:submitted_at].encode("utf-8"))
    @rate         = data[:rate].encode("utf-8").to_i
    @title        = data[:title] ? "*#{data[:title].to_s.encode("utf-8")}*\n" : nil
    @text         = data[:text] ? data[:text].to_s.encode("utf-8") : nil
    @link         = data[:link].to_s.encode("utf-8")
  end

  def self.collection
    @collection ||= []
  end

  def self.send_reviews_from_date(date)
    selected_message = collection.select do |r|
      r.submitted_at > date && (r.title || r.text)
    end
    message = selected_message.sort_by do |r|
      r.submitted_at
    end.map do |r|
      r.build_message
    end.join("\n")

    if message != ""
      Slack.notify(message)
    else
      print "No new reviews\n"
    end
  end


  def notify_to_slack
    if text || title
      message = "*Rating: #{rate}* | version: #{version} | subdate: #{submitted_at}\n #{[title, text].join(" ")}\n <#{url}|Ответить в Google play>"
      Slack.notify(message)
    end
  end

  def build_message
    stars = rate.times.map{"★"}.join + (5 - rate).times.map{"☆"}.join

    [
      "\n\n#{stars}",
      "#{[title, text].join(" ")}",
      "for v#{version} " " <#{link}| Google Play>",
    ].join("\n")
  end
end

#####################
# main scripts
#####################
last_datetime_string = File.read(SENTINEL_DATE_TXT)
datetime = Time.parse(last_datetime_string).to_datetime
file_date = datetime.strftime("%Y%m")
csv_file_name = "reviews_#{CONFIG["package_name"]}_#{file_date}.csv"
system "BOTO_PATH=./secrets/.boto gsutil/gsutil cp -r gs://#{CONFIG["app_repo"]}/reviews/#{csv_file_name} ."

CSV.foreach(csv_file_name, encoding: 'bom|utf-16le', headers: true) do |row|
  next if row[11].nil?
  Review.collection << Review.new({
    version: row[2],
    device: row[4],
    submitted_at: row[5],
    rate: row[9],
    title: row[10],
    text: row[11],
    link: row[15],
  })
end

Review.send_reviews_from_date(datetime)

File.write(SENTINEL_DATE_TXT, Review.collection.last.submitted_at)
