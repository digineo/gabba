# yo, easy server-side tracking for Google Analytics... hey!
require "uri"
require "net/http"
require 'cgi'
require File.dirname(__FILE__) + '/version'

module Gabba
  
  class NoGoogleAnalyticsAccountError < RuntimeError; end
  class NoGoogleAnalyticsDomainError < RuntimeError; end
  class GoogleAnalyticsNetworkError < RuntimeError; end
  
  class Gabba
    GOOGLE_HOST = "www.google-analytics.com"
    BEACON_PATH = "/__utm.gif"
    USER_AGENT = "Gabba #{VERSION} Agent"
    
    attr_accessor :utmwv, :utmn, :utmhn, :utmcs, :utmul, :utmdt, :utmp, :utmac, :utmt, :utmcc, :user_agent
    
    def initialize(ga_acct, domain, agent = Gabba::USER_AGENT)
      @utmwv = "4.4sh" # GA version
      @utmcs = "UTF-8" # charset
      @utmul = "en-us" # language
       
      @utmn = random_id
      @utmhid = random_id
      
      @utmac = ga_acct
      @utmhn = domain
      @user_agent = agent
    end
    
    # Track a page view
    # title - Title of the current page
    # page - Path (URI) of the current page
    # params - Additional params for tracking, i.e.:
    #   :utmip  - the client's IP address
    #   :utmvid - the unique visitor's ID
    def page_view(title, page, params={})
      check_account_params
      hey(page_view_params(title, page).merge(params))
    end

    def page_view_params(title, page)
      default_params.merge \
        :utmdt => title,
        :utmp => page
    end
  
    def event(category, action, label = nil, value = nil, params = {})
      check_account_params
      hey(event_params(category, action, label, value).merge(params))
    end

    def event_params(category, action, label = nil, value = nil)
      default_params.merge \
        :utmt => 'event',
        :utme => event_data(category, action, label, value)
    end

    def event_data(category, action, label = nil, value = nil)
      data = "5(#{category}*#{action}" + (label ? "*#{label})" : ")")
      data += "(#{value})" if value
      data
    end
    
    def transaction(order_id, total, store_name = nil, tax = nil, shipping = nil, city = nil, region = nil, country = nil, params = {})
      check_account_params
      hey(transaction_params(order_id, total, store_name, tax, shipping, city, region, country).merge(params))
    end

    def transaction_params(order_id, total, store_name, tax, shipping, city, region, country)
      # '1234',           // utmtid URL-encoded order ID - required
      # 'Acme Clothing',  // utmtst affiliation or store name
      # '11.99',          // utmtto total - required
      # '1.29',           // utmttx tax
      # '5',              // utmtsp shipping
      # 'San Jose',       // utmtci city
      # 'California',     // utmtrg state or province
      # 'USA'             // utmtco country
      default_params.merge \
        :utmt => 'tran',
        :utmhid => utmhid,
        :utmtid => order_id,
        :utmtst => store_name,
        :utmtto => total,
        :utmttx => tax,
        :utmtsp => shipping,
        :utmtci => city,
        :utmtrg => region,
        :utmtco => country
    end
    
    def add_item(order_id, item_sku, price, quantity, name = nil, category = nil, params = {})
      check_account_params
      hey(item_params(order_id, item_sku, name, category, price, quantity).merge(params))
    end
    
    def item_params(order_id, item_sku, name, category, price, quantity)
      # '1234',           // utmtid URL-encoded order ID - required
      # 'DD44',           // utmipc SKU/code - required
      # 'T-Shirt',        // utmipn product name
      # 'Green Medium',   // utmiva category or variation
      # '11.99',          // utmipr unit price - required
      # '1'               // utmiqt quantity - required
      default_params.merge \
        :utmt => 'item',
        :utmtid => order_id,
        :utmipc => item_sku,
        :utmipn => name,
        :utmiva => category,
        :utmipr => price,
        :utmiqt => quantity
    end
  
    # create magical cookie params used by GA for its own nefarious purposes
    def cookie_params(utma1 = random_id, utma2 = rand(1147483647) + 1000000000, today = Time.now)
      "__utma=1.#{utma1}00145214523.#{utma2}.#{today.to_i}.#{today.to_i}.15;+__utmz=1.#{today.to_i}.1.1.utmcsr=(direct)|utmccn=(direct)|utmcmd=(none);"
    end
    
    protected
    
    def default_params
      {
        :utmwv => @utmwv,
        :utmn => @utmn,
        :utmhn => @utmhn,
        :utmcs => @utmcs,
        :utmul => @utmul,
        :utmac => @utmac,
        :utmcc => @utmcc || cookie_params
      }
    end

    # sanity check that we have needed params to even call GA
    def check_account_params
      raise NoGoogleAnalyticsAccountError unless @utmac
      raise NoGoogleAnalyticsDomainError unless @utmhn
    end

    # makes the tracking call to Google Analytics
    def hey(params)
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