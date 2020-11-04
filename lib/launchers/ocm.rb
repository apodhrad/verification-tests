#!/usr/bin/env ruby

lib_path = File.expand_path(File.dirname(File.dirname(__FILE__)))
unless $LOAD_PATH.any? {|p| File.expand_path(p) == lib_path}
  $LOAD_PATH.unshift(lib_path)
end

require 'common'
require 'json'

module BushSlicer
  class OCM
    include Common::Helper

    attr_reader :config
    attr_reader :token, :token_file, :url, :region

    def initialize(**options) 
      service_name = options[:service_name] ||
                     ENV['OCM_SERVICE_NAME'] ||
                     'ocm'
      @opts = default_opts(service_name).merge options

      @token = ENV['OCM_TOKEN'] || @opts[:token]
      @token_file = @opts[:token_file]
      unless @token
        if @token_file
          token_file_path = expand_private_path(@token_file)
          @token = File.read(token_file_path)
        else
          raise "You need to specify OCM token by 'token' or by 'token_file'"
        end
      end
      @url = ENV['OCM_URL'] || @opts[:url] || 'https://api.stage.openshift.com'
      @region = ENV['OCM_REGION'] || @opts[:region]
    end

    # @param service_name [String] the service name of this openstack instance
    #   to lookup in configuration
    def default_opts(service_name)
      return  conf[:services, service_name.to_sym]
    end

    def generate_json_file
      json_data = {
        "name" => "myosd4",
        "managed" => "true"
      }
      if @region
        new_data = { "region" => { "id" => @region } }
        json_data.merge!(new_data)
      end
      json_file = Tempfile.new("ocm.json", Host.localhost.workdir)
      puts json_file.path
      File.open(json_file,"w") do |f|
        f.write(json_data.to_json)
      end
      puts json_file.read 
    end

  end

end
