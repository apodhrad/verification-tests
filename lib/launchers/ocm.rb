#!/usr/bin/env ruby

lib_path = File.expand_path(File.dirname(File.dirname(__FILE__)))
unless $LOAD_PATH.any? {|p| File.expand_path(p) == lib_path}
  $LOAD_PATH.unshift(lib_path)
end

require 'common'
require 'json'
require 'tmpdir'

module BushSlicer
  class OCM
    include Common::Helper

    attr_reader :config
    attr_reader :token, :token_file, :url, :region, :version, :nodes, :lifespan, :cloud, :cloud_opts, :multi_az

    def initialize(**options) 
      service_name = ENV['OCM_SERVICE_NAME'] || options[:service_name] || 'ocm'
      @opts = default_opts(service_name)&.merge options
      unless @opts
        @opts = options
      end

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
      @region = ENV['OCM_REGION'] || ENV['AWS_REGION'] || @opts[:region]
      @version = ENV['OCM_VERSION'] || @opts[:version]
      @nodes = ENV['OCM_NODES'] || @opts[:nodes]
      @lifespan = ENV['OCM_LIFESPAN'] || @opts[:lifespan]
      @multi_az = ENV['OCM_MULTI_AZ'] || @opts[:multi_az]

      @cloud = ENV['OCM_CLOUD'] || @opts[:cloud]
      if @cloud
        @cloud_opts = default_opts(@cloud)
        unless @cloud_opts
          raise "Cannot find cloud '#{cloud}' defined in '#{service_name}'"
        end
      end
    end

    # @param service_name [String] the service name of this openstack instance
    #   to lookup in configuration
    def default_opts(service_name)
      return  conf[:services, service_name.to_sym]
    end

    def generate_json(name)
      json_data = {
        "name" => name,
        "managed" => true,
        "multi_az" => false,
        "byoc" => false
      }

      if @multi_az
        json_data.merge!({"multi_az" => @multi_az})
      end

      if @region
        json_data.merge!({"region" => {"id" => @region}})
      end

      if @version
        json_data.merge!({"version" => {"id" => "openshift-v#{@version}"}})
      end

      if @nodes
        json_data.merge!({"nodes" => {"compute" => @nodes}})
      end

      if @lifespan
        expiration = Time.now + 60 * 60 * @lifespan.to_i
        json_data.merge!({"expiration_timestamp" => expiration.strftime("%Y-%m-%dT%H:%M:%SZ")})
      end

      if @cloud_opts
        case @cloud_opts[:cloud_type]
        when "aws"
          aws = Amz_EC2.new(service_name: @cloud)
          json_data.merge!({"aws" => {"access_key_id":aws.access_key, "secret_access_key":aws.secret_key, "account_id":aws.account_id}})
          json_data.merge!({"byoc" => true})
        end
      end

      return json_data.to_json
    end

    def download_osd_script
      # we can consider putting the script directly into this repo
      # we can also consider cloning the full git repo but downloading a single file is much faster
      default_osd_script_url = "https://gitlab.cee.redhat.com/apodhrad/mk-performance-tests/-/raw/curl/scripts/osd-provision.sh?inline=false"
      osd_script_url = ENV['OSD_SCRIPT_URL'] || default_osd_script_url
      # we need another parent dir as the downloaded script downloads ocm tool to its parent
      osd_scripts = "#{Dir.tmpdir}/osd-scripts"
      %x(
        rm -rf #{osd_scripts} && mkdir #{osd_scripts} && \
        curl -s #{osd_script_url} --output #{osd_scripts}/osd-provision.sh && \
        chmod a+x #{osd_scripts}/osd-provision.sh
      )
      return "#{osd_scripts}/osd-provision.sh"
    end

    def create_osd(name)
      # cerate a temp file with ocm-token
      ocm_token_file = Tempfile.new("ocm-token-file", Host.localhost.workdir)
      File.open(ocm_token_file, "w") do |f|
        f.write(@token)
      end
      # create a temp file with cluster specification
      puts File.read(ocm_token_file.path)
      ocm_json_file = Tempfile.new("ocm-json-file", Host.localhost.workdir)
      File.open(ocm_json_file, "w") do |f|
        f.write(generate_json(name))
      end
      # now, download the script with we can create the OSD cluster
      osd_script = download_osd_script
      system("#{osd_script} --create --cloud-token-file #{ocm_token_file.path} -f #{ocm_json_file.path} --wait")
      system("#{osd_script} --get api_url -f #{ocm_json_file.path}")
      system("#{osd_script} --get credentials -f #{ocm_json_file.path}")
    end

    def delete_osd(name)
      ocm_token_file = Tempfile.new("ocm-token-file", Host.localhost.workdir)
      File.open(ocm_token_file, "w") do |f|
        f.write(@token)
      end
      ocm_json_file = Tempfile.new("ocm-json-file", Host.localhost.workdir)
      File.open(ocm_json_file, "w") do |f|
        f.write(generate_json(name))
      end
      osd_script = download_osd_script
      system("#{osd_script} --delete --cloud-token-file #{ocm_token_file.path} -f #{ocm_json_file.path}")
    end

  end

end
