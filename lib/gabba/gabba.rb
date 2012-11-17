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
    
    # Custom var levels
    VISITOR = 1
    SESSION = 2
    PAGE    = 3
    
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
      
      @custom_vars = []
    end
    

    # Public: Set a custom variable to be passed along and logged by Google Analytics
    # (http://code.google.com/apis/analytics/docs/tracking/gaTrackingCustomVariables.html)
    #
    # index  - Integer between 1 and 50 for this custom variable (limit is 5 normally, but is 50 for GA Premium)
    # name   - String with the name of the custom variable
    # value  - String with the value for teh custom variable
    # scope  - Integer with custom variable scope must be 1 (VISITOR), 2 (SESSION) or 3 (PAGE)
    #
    # Example:
    #
    #   g = Gabba::Gabba.new("UT-1234", "mydomain.com")
    #   g.set_custom_var(1, 'awesomeness', 'supreme', Gabba::VISITOR)
    #   # => ['awesomeness', 'supreme', 1]
    #
    # Returns array with the custom variable data
    def set_custom_var(index, name, value, scope)
      raise "Index must be between 1 and 50" unless (1..50).include?(index)
      raise "Scope must be 1 (VISITOR), 2 (SESSION) or 3 (PAGE)" unless (1..3).include?(scope)

      @custom_vars[index] = [ name, value, scope ]
    end

    # Public: Delete a previously set custom variable so if is not passed along and logged by Google Analytics
    # (http://code.google.com/apis/analytics/docs/tracking/gaTrackingCustomVariables.html)
    #
    # index  - Integer between 1 and 5 for this custom variable
    #
    # Example:
    #   g = Gabba::Gabba.new("UT-1234", "mydomain.com")
    #   g.delete_custom_var(1)
    #
    def delete_custom_var(index)
      raise "Index must be between 1 and 5" unless (1..5).include?(index)

      @custom_vars.delete_at(index)
    end

    # Public: Renders the custom variable data in the format needed for GA
    # (http://code.google.com/apis/analytics/docs/tracking/gaTrackingCustomVariables.html)
    # Called before actually sending the data along to GA.
    def custom_var_data
      names  = []
      values = []
      scopes = []

      idx = 1
      @custom_vars.each_with_index do |(n, v, s), i|
        next if !n || !v || (/\w/ !~ n) || (/\w/ !~ v)
        prefix = "#{i}!" if idx != i
        names  << "#{prefix}#{URI.escape(n)}"
        values << "#{prefix}#{URI.escape(v)}"
        scopes << "#{prefix}#{URI.escape(s)}"
        idx = i + 1
      end

      names.empty? ? nil : "8(#{names.join('*')})9(#{values.join('*')})11(#{scopes.join('*')})"
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
        :utmp  => page,
        :utme  => custom_var_data
      )
    end
  
    def event(category, action, label = nil, value = nil, params = {})
      hey event_params(category, action, label, value, params)
    end

    def event_params(category, action, label = nil, value = nil, params)
      build_params params.merge(
        :utmt => 'event',
        :utme => event_data(category, action, label, value) << custom_var_data.to_s
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