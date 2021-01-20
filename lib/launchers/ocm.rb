#!/usr/bin/env ruby

lib_path = File.expand_path(File.dirname(File.dirname(__FILE__)))
unless $LOAD_PATH.any? {|p| File.expand_path(p) == lib_path}
  $LOAD_PATH.unshift(lib_path)
end

require 'common'
require 'json'
require 'yaml'
require 'tmpdir'
require 'git'

module BushSlicer
  class OCM
    include Common::Helper

    attr_reader :config
    attr_reader :token, :token_file, :url, :region, :version, :num_nodes, :lifespan, :cloud, :cloud_opts, :multi_az, :aws_account_id, :aws_access_key, :aws_secret_key

    def initialize(**options) 
      service_name = ENV['OCM_SERVICE_NAME'] || options[:service_name] || 'ocm'
      @opts = default_opts(service_name)&.merge options
      unless @opts
        @opts = options
      end

      # OCM token is mandatory
      # it can be defined by token or by token_file
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

      # region is mandatory
      # in the future we can extend support for other clouds, e.g. GCP and ARO
      @region = ENV['OCM_REGION'] || ENV['AWS_REGION'] || @opts[:region]

      # url defines the OCM environment (prod, integration or stage)
      # currently, the url is ignored as many teams use the stage environment
      @url = ENV['OCM_URL'] || @opts[:url] || 'https://api.stage.openshift.com'

      # openshift version is optional
      @version = ENV['OCM_VERSION'] || ENV['OCP_VERSION'] || @opts[:version]

      # number of worker nodes
      # minimum is 2
      # default value is 4
      @num_nodes = ENV['OCM_NUM_NODES'] || @opts[:num_nodes]

      # lifespan in hours
      # default value is 24 hours
      @lifespan = ENV['OCM_LIFESPAN'] || @opts[:lifespan]

      # multi_az is optional
      # default value is false
      @multi_az = ENV['OCM_MULTI_AZ'] || @opts[:multi_az]

      # BYOC (Bring Your Own Cloud)
      # you can refer to already defined cloud in config.yaml
      # currently, only AWS is supported
      if ENV['AWS_ACCOUNT_ID'] && ENV['AWS_ACCESS_KEY'] && (ENV['AWS_SECRET_ACCESS_KEY'] || ENV['AWS_SECRET_KEY'])
        @aws_account_id = ENV['AWS_ACCOUNT_ID']
        @aws_access_key = ENV['AWS_ACCESS_KEY']
        @aws_secret_key = ENV['AWS_SECRET_ACCESS_KEY'] || ENV['AWS_SECRET_KEY']
      else
        @cloud = ENV['OCM_CLOUD'] || @opts[:cloud]
        if @cloud
          @cloud_opts = default_opts(@cloud)
          unless @cloud_opts
            raise "Cannot find cloud '#{cloud}' defined in '#{service_name}'"
          end
          case @cloud_opts[:cloud_type]
          when "aws"
            aws = Amz_EC2.new(service_name: @cloud)            
            @aws_account_id = aws.account_id
            @aws_access_key = aws.access_key
            @aws_secret_key = aws.secret_key
          end
        end
      end
    end

    # @param service_name [String] the service name of this openstack instance
    #   to lookup in configuration
    def default_opts(service_name)
      return  conf[:services, service_name.to_sym]
    end

    private :default_opts

    def to_seconds(string)
      regex_m = /^(\d+)\s*(m|min|minutes|mins)+$/
      regex_h = /^(\d+)\s*(h|hour|hours|hrs)+$/
      regex_d = /^(\d+)\s*(d|day|days)+$/
      regex_w = /^(\d+)\s*(w|week|weeks|wks)+$/
      case string
      when regex_m
        return string.match(regex_m)[1].to_i * 60
      when regex_h
        return string.match(regex_h)[1].to_i * 60 * 60
      when regex_d
        return string.match(regex_d)[1].to_i * 24 * 60 * 60
      when regex_w
        return string.match(regex_w)[1].to_i * 7 * 24 * 60 * 60
      else
        raise "Cannot convert '#{string}' to seconds!"
      end
    end

    # create a json which specifies OSD cluster
    # in the future we plan to move the logic into the script 'osd-provision.sh'
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

      if @num_nodes
        json_data.merge!({"nodes" => {"compute" => @num_nodes.to_i}})
      end

      if @lifespan
        expiration = Time.now + to_seconds(@lifespan)
        json_data.merge!({"expiration_timestamp" => expiration.strftime("%Y-%m-%dT%H:%M:%SZ")})
      end

      if @aws_account_id && @aws_access_key && @aws_secret_key
        json_data.merge!({"aws" => {"account_id":@aws_account_id, "access_key_id":@aws_access_key, "secret_access_key":@aws_secret_key}})
        json_data.merge!({"byoc" => true})
      end

      return json_data.to_json
    end

    # download the script 'osd-provision.sh' which takes care of the OSD installation/uninstallation
    def download_osd_script
      osd_repo_uri = ENV['GIT_OSD_URI'] || 'https://gitlab.cee.redhat.com/mk-bin-packing/mk-performance-tests.git'
      osd_repo_dir = File.join(Dir.tmpdir, 'osd_repo')
      FileUtils.rm_rf(osd_repo_dir)
      git = BushSlicer::Git.new(uri: osd_repo_uri, dir: osd_repo_dir)
      git.clone
      osd_script = File.join(osd_repo_dir, 'scripts', 'osd-provision.sh')
      if !File.exists?(osd_script)
        raise "Cannot find #{osd_script}"
      end
      return osd_script
    end

    def shell(cmd, output = nil)
      if output
        res = Host.localhost.exec(cmd, single: true, stderr: :stdout, stdout: output, timeout: 3600)
      else
        res = Host.localhost.exec(cmd, single: true, timeout: 3600)
      end
      if res[:success]
        return res[:response]
      else
        raise "Error when executing '#{cmd}'. Response: #{res[:response]}"
      end
    end

    # generate OCP information
    def generate_ocp_info(api_url, json_creds)
      api_regex = /https?:\/\/api\.([\S]+):[\d]*/
      if api_url.match(api_regex)
        domain = api_url.scan(api_regex).first.first
      else
        raise "Given api_url '#{api_url}' doesn't match '#{api_regex}'"
      end
      credentials = JSON.parse(json_creds)
      ocp_info = {
        "ocp_domain" => domain,
        "ocp_api_url" => "https://api.#{domain}:6443",
        "ocp_console_url" => "https://console-openshift-console.apps.#{domain}",
        "user" => credentials["user"],
        "password" => credentials["password"]
      }
      return ocp_info
    end

    # create OSD cluster
    def create_osd(name)
      # cerate a temp file with ocm-token
      ocm_token_file = Tempfile.new("ocm-token-file", Host.localhost.workdir)
      File.write(ocm_token_file, @token)
      # create cluster.json in a workdir/install-dir
      install_dir = File.join(Host.localhost.workdir, 'install-dir')
      FileUtils.mkdir_p(install_dir)
      ocm_json_file = File.join(install_dir, 'cluster.json')
      File.write(ocm_json_file, generate_json(name))
      # now, download the script which will take care of the OSD cluster installation
      osd_script = download_osd_script
      shell("#{osd_script} --create --cloud-token-file #{ocm_token_file.path} -f #{ocm_json_file} --wait", STDOUT)
      output = shell("#{osd_script} --get api_url -f #{ocm_json_file}")
      ocp_api_url = output.lines.last
      output = shell("#{osd_script} --get credentials -f #{ocm_json_file}")
      ocp_credentials = output.lines.last
      # generate yaml file with OCP information
      ocp_info_file = File.join(install_dir, 'OCPINFO.yml')
      File.write(ocp_info_file, generate_ocp_info(ocp_api_url, ocp_credentials).to_yaml)
    end

    # delete OSD cluster
    def delete_osd(name)
      # create a temp file with ocm-token
      ocm_token_file = Tempfile.new("ocm-token-file", Host.localhost.workdir)
      File.write(ocm_token_file, @token)
      # now, download the script which will take care of the OSD cluster installation
      osd_script = download_osd_script
      shell("#{osd_script} --delete --cloud-token-file #{ocm_token_file.path} -n #{name}")
    end

  end

end
