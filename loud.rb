require 'yaml'
require 'twitter'
require 'tire'

module Cinch::Plugins
  module LOUD

    class ES
      LOUD_INDEX = 'louds'

      class << self
        attr_accessor :last_loud
      end

      def initialize
        @index = Tire.index('louds')
        randomloud
      end

      def randomloud
        result = Tire.search('louds') do 
          query do 
            boolean do
              must { string 'score:[1 TO *]' }
            end
          end

          sort do
            by :_script => { :script => "random()", :type => "number", :order => "desc" }
          end
        end.results.first

        self.class.last_loud = result
      end

      def add_loud(loud, channel, nick)
        @index.store(:loud => loud, :channel => channel, :nick => nick, :score => 1)
        @index.refresh
      end

      def search(pattern)
        results = Tire.search('louds') do
          query do
            string pattern.upcase
          end
          sort do
            by :_script => { :script => "random()", :type => "number", :order => "desc" }
          end
        end.results.to_a.last(5)

        self.class.last_loud = results[-1]
        results
      end

      def searchterm(term)
        results = Tire.search('louds') do
          query do
            boolean do
              must { string term }
            end
          end
          sort do
            by :_script => { :script => "random()", :type => "number", :order => "desc" }
          end
        end.results.to_a.last(5)

        self.class.last_loud = results[-1]
        results
      end

      def bump
        ll = self.class.last_loud.to_hash
        ll[:score] = (self.class.last_loud.score.to_i + 1).to_s
        @index.store(ll)
        @index.refresh
        self.class.last_loud = @index.retrieve('document', ll[:id])
      end

      def sage
        ll = self.class.last_loud.to_hash
        ll[:score] = (self.class.last_loud.score.to_i - 1).to_s
        @index.store(ll)
        @index.refresh
        self.class.last_loud = @index.retrieve('document', ll[:id])
      end
      
      def score
        return "#{self.class.last_loud[:loud]}: #{self.class.last_loud[:score]}"
      end

      def whosaid
        return "#{self.class.last_loud[:loud]}: #{self.class.last_loud[:nick] || "unknown"} (#{self.class.last_loud[:channel] || "unknown"})"
      end

      def twitlast
        self.class.last_loud[:loud]
      end
    end

    class TWIT
      def initialize(*args)
        conf = YAML.load_file( 'oauth.yml' )
        Twitter.configure do |config|
          config.consumer_key = conf["oauth"]["consumer_key"]
          config.consumer_secret = conf["oauth"]["consumer_secret"]
          config.oauth_token = conf["oauth"]["oauth_token"]
          config.oauth_token_secret = conf["oauth"]["oauth_token_secret"]
        end
        @twit = Twitter.new
      end

      def post(text)
        @last_tweet = @twit.update(text)
      end

      def get_last
        if @last_tweet
          "http://twitter.com/#!/loudbot/status/" + @last_tweet[:id].to_s
        else
          ""
        end
      end
    end

    class LISTEN
      include Cinch::Plugin

      def initialize(*args)
        super
        @twit = TWIT.new
      end

      match "twitlast"
      self.react_on = :channel

      def execute(m)
        @twit.post(ES.last_loud[:loud])
        m.reply @twit.get_last
      end
    end

    class BEINGLOUD
      include Cinch::Plugin

      MIN_LENGTH = 10

      def initialize(*args)
        super
        @db = ES.new
      end

      match %r/^([A-Z0-9\W]{#{MIN_LENGTH},})$/, :use_prefix => false, :use_suffix => false
      self.react_on = :channel

      def execute(m, query)
        if query =~ /[A-Z]/ and
            query.scan(/[A-Z\s0-9]/).length > query.scan(/[^A-Z\s0-9]/).length and
            !query.include?(m.bot.nick)

          @db.add_loud(query, m.channel.name, m.user.nick)
          m.reply(@db.randomloud[:loud])
        end
      end
    end

    class TALKINGTOLOUD
      include Cinch::Plugin

      def initialize(*args)
        super
        @db = ES.new
      end

      self.prefix = lambda { |m| m.bot.nick }
      match %r/.*/, :use_prefix => true, :use_suffix => false

      def execute(m)
        m.reply(@db.randomloud[:loud])
      end
    end

    class LOUDSEARCH
      include Cinch::Plugin

      def initialize(*args)
        super
        @db = ES.new 
      end

      match %r!(search(?:term)?)\s*(.+)!, :use_prefix => true
      self.react_on = :channel

      def execute(m, command, query)
        case command
        when 'search'
          @db.search(query.upcase).each do |loud|
            m.reply(loud[:loud])
          end
        when 'searchterm'
          @db.searchterm(query).each do |loud|
            m.reply(loud[:loud])
          end
        end
      end
    end

    class LOUDMETA
      include Cinch::Plugin

      def initialize(*args)
        super
        @db = ES.new
      end

      match %r/(whosaid|bump|sage|score)$/, :use_prefix => true, :use_suffix => false
      self.react_on = :channel

      def execute(m, query)
        case query
        when 'bump'
          @db.bump
        when 'sage'
          @db.sage
        when 'score'
          m.reply(@db.score)
        when 'whosaid'
          m.reply(@db.whosaid)
        end
      end
    end

    class LOUDDONG
      include Cinch::Plugin
      match %r/dongs?$/, :use_prefix => true, :use_suffix => false
      self.react_on = :channel

      def execute(m)
        m.reply("8" + ('=' * (rand(20).to_i + 1)) + "D")
      end
    end

    class LOUDTACO
      include Cinch::Plugin

      match %r/tacome$/, :use_prefix => true, :use_suffix => false

      def execute(m)
        m.reply("http://i.imgur.com/ynrKx.gif")
      end
    end
  end
end
