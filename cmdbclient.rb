#!ruby

require 'net/http'
require 'net/https'
require 'rubygems'
require 'json'

class CMDBclient

    @@mocked = false

    def self.mock!
        @@mocked = true
    end

    def initialize(opt)
        @delegate = (@@mocked ? CMDBclient::Mock.new(opt) :
            CMDBclient::Real.new(opt))
    end

    def delegate
        @delegate
    end

    def dbg(msg)
        if @opt.has_key? 'debug' and @opt['debug'] > 1
            puts "DBG(CMDBclient): #{msg}"
        end
    end

    def trim(s, c='/', dir=:both)
        case dir
        when :both
            trim(trim(s, c, :right), c, :left)
        when :right
            s.sub(Regexp.new(c + '+/'), '')
        when :left
            s.sub(Regexp.new('^' + c + '+'), '')
        end
    end

    def ltrim(s, c='/')
        trim(s, c, :left)
    end

    def rtrim(s, c='/')
        trim(s, c, :right)
    end

    def method_missing(meth, *args, &block)
        @delegate.send(meth, *args, &block)
    end

end

class CMDBclient::Real < CMDBclient

    def initialize(opt)
        @opt = opt
        self.dbg "Initialized with options: #{opt.inspect}"
    end

    def do_request(opt={})
        method = [:GET, :PUT].find do |m|
            opt.has_key? m
        end
        method ||= :GET
        rel_uri = opt[method]
        url = URI.parse(@opt['cmdb']['url'])
        url.path = rtrim(url.path) + '/' + ltrim(rel_uri)
        url.query = opt[:query] if opt.has_key? :query
        self.dbg("#{method.inspect} => #{url.to_s}")
        http = Net::HTTP.new(url.host, url.port)
        http.use_ssl=true if url.scheme == 'https'
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        reqclass = case method
                   when :GET
                       Net::HTTP::Get
                   when :PUT
                       Net::HTTP::Put
                   end
        request = reqclass.new(url.request_uri)
        self.dbg request.to_s
        if @opt['cmdb'].has_key? 'username'
            request.basic_auth(@opt['cmdb']['username'],
                          @opt['cmdb']['password'])
        end
        request.body = opt[:body].to_json if opt.has_key? :body
        response = http.request(request)
        self.dbg response.to_s
        if response.code[0] != ?2
            raise "Error making cmdb request (#{response.code}): " +
                error_body(response.body)
        end

        if response.body
            JSON.parse(response.body)
        else
            true
        end
    end

    def query(type, *condlist)
        do_request(:GET => "#{type}", :query => condlist.join('&'))
    end

    def key_field_of(type)
        case type
        when 'system'
            'fqdn'
        else
            'id'
        end
    end

    def error_body(body_text)
        begin
            JSON.parse(body_text)["message"]
        rescue
            body_text
        end
    end

    def get_or_assign_system_name(serial)
        do_request :GET => "pcmsystemname/#{serial}"
    end

    def update(type, obj, key=nil)
        key ||= obj[key_field_of(type)]
        do_request(:PUT => "#{type}/#{key}", :body => obj)
    end

    def tc_post(obj)
        # Post the object to trafficcontrol
        # obj is something you can call .to_json on
        url = URI.parse(@opt['trafficcontrol']['url'])
        self.dbg "Posting to #{url.inspect}"
        res = Net::HTTP.start(url.host, url.port) do |http|
            self.dbg "Connected to #{url.host}:#{url.port}"
            req = Net::HTTP::Post.new(url.path)
            req.body = obj.to_json
            self.dbg "BODY = #{obj.to_json}"
            if @opt['trafficcontrol'].has_key? 'username'
                self.dbg "   using username #{@opt['trafficcontrol']['username']}"
                self.dbg "   using password #{@opt['trafficcontrol']['password']}"
                req.basic_auth @opt['trafficcontrol']['username'], @opt['trafficcontrol']['password']
            end
            self.dbg "Sending request #{req.inspect}"
            http.request(req)
        end
        self.dbg res.inspect
        if res.code[0] == ?2
            self.dbg "   success (#{res.code})"
            true
        else
            raise "Error posting to TC: #{res}"
        end
    end

end

class CMDBclient::Mock < CMDBclient

    def initialize(opt)
        @system_index = 3
        @dclist = ['SNV', 'AWSLAB']
        @data = {
            'm0000001.lab.ppops.net' => {
                'fqdn' => 'm0000001.lab.ppops.net',
                'roles' => '',
                'status' => 'idle',
                'environment_name' => 'lab',
                'ip_address' => '10.0.0.1',
                'created_by' => 'user1',
                'serial' => 's-001',
                'data_center_code' => 'SNV'
            },
            'm0000002.lab.ppops.net' => {
                'fqdn' => 'm0000002.lab.ppops.net',
                'roles' => 'pcm-api-v2::role',
                'ip_address' => '10.0.0.1',
                'created_by' => 'user2',
                'serial' => 's-002',
                'data_center_code' => 'AWSLAB'
            }
        }
    end

    def query(type, *condlist)
        raise "Unimplemented type #{type}" unless type == 'system'
        if condlist.empty?
            @data.map { |k, v| v }
        else
            cond = condlist.first
            if m = /^fqdn=([^&]+)/.match(cond)
                fqdn = m[1]
                if @data.has_key? fqdn
                    [@data[fqdn]]
                else
                    []
                end
            else
                raise "Unimplemented complex query #{condlist.join('&')}"
            end
        end
    end

    def update(type, obj, key=nil)
        raise "Unimplemented type #{type}" unless type == 'system'

        key ||= obj['fqdn']

        raise "404 Not Found" unless @data.has_key? key
        @data[key].update(obj)
    end

    def get_or_assign_system_name(serial)
        @data.values.find { |s| s['serial'] == serial } || new_name(serial)
    end

    def new_name(serial)
        fqdn = sprintf('m%07i.lab.ppops.net', @system_index)
        @system_index += 1
        @data[fqdn] = { 'fqdn' => fqdn,
            'serial' => serial
        }
    end

end
