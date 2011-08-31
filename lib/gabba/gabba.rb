# yo, easy server-side tracking for Google Analytics... hey!
require "uri"
require "net/http"
require 'cgi'
require File.dirname(__FILE__) + '/version'

# 
# Inspired by
#  https://gist.github.com/533053
# 
# The GIF Request Parameters:
#  https://code.google.com/intl/de-DE/apis/analytics/docs/tracking/gaTrackingTroubleshooting.html#gifParameters
# 
module Gabba
  
  class NoGoogleAnalyticsAccountError < RuntimeError; end
  class NoGoogleAnalyticsDomainError < RuntimeError; end
  class GoogleAnalyticsNetworkError < RuntimeError; end
  
  class Gabba
    GOOGLE_HOST = "www.google-analytics.com"
    BEACON_PATH = "/__utm.gif"
    USER_AGENT = "Gabba #{VERSION} Agent"
    
    # Asynchronous HTTP-Requests?
    cattr_accessor :async
    self.async = true
    
    attr_accessor :utmwv, :utmn, :utmhn, :utmcs, :utmdt, :utmp, :utmac, :user_agent
    
    def initialize(account, domain, agent = Gabba::USER_AGENT)
      raise NoGoogleAnalyticsAccountError if account !~ /^MO-\d+-\d+$/
      raise NoGoogleAnalyticsDomainError if domain.blank?
      
      @utmwv = "4.4sh" # GA version
      @utmcs = "UTF-8" # charset
      @utmn  = random_id # Unique ID (random number) generated for each request
      @utmac = account # account string (MO-xxxxxxx-x)
      @utmhn = domain
      @user_agent = agent
    end
    
    # Track a page view
    # title - Title of the current page
    # page - Path (URI) of the current page
    # params - Additional params for tracking, i.e.:
    #   :utmip  - the client's IP address
    def page_view(title, page, params={})
      hey page_view_params(title, page, params)
    end

    def page_view_params(title, page, params)
      build_params params.merge(
        :utmdt => title,
        :utmp  => page
      )
    end
  
    def event(category, action, label = nil, value = nil, params = {})
      hey event_params(category, action, label, value, params)
    end

    def event_params(category, action, label = nil, value = nil, params)
      build_params params.merge(
        :utmt => 'event',
        :utme => event_data(category, action, label, value)
      )
    end

    def event_data(category, action, label = nil, value = nil)
      data = "5(#{category}*#{action}" + (label ? "*#{label})" : ")")
      data += "(#{value})" if value
      data
    end
    
    def transaction(order_id, total, store_name = nil, tax = nil, shipping = nil, city = nil, region = nil, country = nil, params = {})
      hey transaction_params(order_id, total, store_name, tax, shipping, city, region, country, params)
    end

    def transaction_params(order_id, total, store_name, tax, shipping, city, region, country, params)
      # '1234',           // utmtid URL-encoded order ID - required
      # 'Acme Clothing',  // utmtst affiliation or store name
      # '11.99',          // utmtto total - required
      # '1.29',           // utmttx tax
      # '5',              // utmtsp shipping
      # 'San Jose',       // utmtci city
      # 'California',     // utmtrg state or province
      # 'USA'             // utmtco country
      build_params params.merge(
        :utmt => 'tran',
        :utmtid => order_id,
        :utmtst => store_name,
        :utmtto => total,
        :utmttx => tax,
        :utmtsp => shipping,
        :utmtci => city,
        :utmtrg => region,
        :utmtco => country
      )
    end
    
    def add_item(order_id, item_sku, price, quantity, name = nil, category = nil, params = {})
      hey item_params(order_id, item_sku, name, category, price, quantity, params)
    end
    
    def item_params(order_id, item_sku, name, category, price, quantity, params)
      # '1234',           // utmtid URL-encoded order ID - required
      # 'DD44',           // utmipc SKU/code - required
      # 'T-Shirt',        // utmipn product name
      # 'Green Medium',   // utmiva category or variation
      # '11.99',          // utmipr unit price - required
      # '1'               // utmiqt quantity - required
      build_params params.merge(
        :utmt   => 'item',
        :utmtid => order_id,
        :utmipc => item_sku,
        :utmipn => name,
        :utmiva => category,
        :utmipr => price,
        :utmiqt => quantity
      )
    end
    
    protected
    
    def build_params(h)
      {
        :utmac => @utmac,
        :utmwv => @utmwv,
        :utmn  => @utmn,
        :utmhn => @utmhn,
        :utmcs => @utmcs,
        :utmcc => '__utma=999.999.999.999.999.1;'
      }.merge(h)
    end

    def hey(params)
      if async
        Thread.new { hey_sync(params) }
      else
        hey_sync(params)
      end
    end
    
    # makes the tracking call to Google Analytics
    def hey_sync(params)
      user_agent = params.delete(:user_agent) || user_agent
      
      query = params.map {|k,v| "#{k}=#{URI.escape(v.to_s, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))}" }.join('&')
      response = Net::HTTP.start(GOOGLE_HOST) do |http|
        request = Net::HTTP::Get.new("#{BEACON_PATH}?#{query}")
        request["User-Agent"] = URI.escape(user_agent)
        request["Accept"] = "*/*"
        http.request(request)
      end

      raise GoogleAnalyticsNetworkError unless response.code == "200"
      response
    end

    def random_id
      rand 8999999999 + 1000000000
    end
        
  end # Gabba Class

end