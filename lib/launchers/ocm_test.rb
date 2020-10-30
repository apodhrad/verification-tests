ENV['BUSHSLICER_PRIVATE_DIR'] = nil
ENV['OCM_NAME'] = nil
ENV['OCM_TOKEN'] = nil
ENV['OCM_URL'] = nil
ENV['OCM_REGION'] = nil
ENV['OCM_VERSION'] = nil
ENV['OCM_LIFESPAN'] = nil

lib_path = File.expand_path(File.dirname(File.dirname(__FILE__)))
unless $LOAD_PATH.any? {|p| File.expand_path(p) == lib_path}
  $LOAD_PATH.unshift(lib_path)
end

require 'fileutils'
require 'test/unit'
require_relative './ocm'

class MyTest < Test::Unit::TestCase
  def setup
    
  end

  # def teardown
  # end

  def test_default_url
    options = { :token => "abc" }
    ocm = BushSlicer::OCM.new(options)
    assert_equal('https://api.stage.openshift.com', ocm.url)
  end

  def test_generating_json
    options = { :token => "abc" }
    ocm = BushSlicer::OCM.new(options)
    json = ocm.generate_json('myosd4')
    assert_equal('{"name":"myosd4","managed":true,"multi_az":false,"byoc":false}', json)
  end

  def test_generating_json_with_region
    options = { :token => "abc", :region => "us-east-1" }
    ocm = BushSlicer::OCM.new(options)
    json = ocm.generate_json('myosd4')
    assert_equal('{"name":"myosd4","managed":true,"multi_az":false,"byoc":false,"region":{"id":"us-east-1"}}', json)
  end

  def test_generating_json_with_version
    options = { :token => "abc", :version => "4.6.1" }
    ocm = BushSlicer::OCM.new(options)
    json = ocm.generate_json('myosd4')
    assert_equal('{"name":"myosd4","managed":true,"multi_az":false,"byoc":false,"version":{"id":"openshift-v4.6.1"}}', json)
  end

  def test_generating_json_with_lifespan
    options = { :token => "abc", :lifespan => "25h" }
    ocm = BushSlicer::OCM.new(options)
    json = ocm.generate_json('myosd4')
    time = Time.now + 60 * 60 * 25
    year = time.strftime("%Y")
    month = time.strftime("%m")
    day = time.strftime("%d")
    assert_match(/.*"expiration_timestamp":"#{year}-#{month}-#{day}T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z".*/, json)
  end

  def test_generating_json_with_nodes
    options = { :token => "abc", :nodes => "8" }
    ocm = BushSlicer::OCM.new(options)
    json = ocm.generate_json('myosd4')
    assert_equal('{"name":"myosd4","managed":true,"multi_az":false,"byoc":false,"nodes":{"compute":8}}', json)
  end

  def test_downloading_osd_script
    options = { :token => "abc" }
    ocm = BushSlicer::OCM.new(options)
    osd_script = ocm.download_osd_script
    assert(File.exists?(osd_script), "File 'osd-provision.sh' was not downloaded")
    content = File.read(osd_script)
    assert_match(/.*ocm.*/, content)
  end

  def test_executing_shell
    hello_script = "/tmp/hello.sh"
    File.write(hello_script, "#!/bin/sh\n[[ -z \"$1\" ]] && echo \"Specify a name!\" && exit 1; for i in {1..3}; do echo \"Hello $1\"; sleep 5; done")
    File.chmod(0755, hello_script)
    options = { :token => "abc" }
    ocm = BushSlicer::OCM.new(options)
    result = ocm.shell("#{hello_script} World")
    assert_equal("Hello World\nHello World\nHello World\n", result)
    result = ocm.shell("#{hello_script} World", STDOUT)
    assert_equal("", result)
    error = assert_raises(RuntimeError) { ocm.shell("#{hello_script} ") }
    assert_equal("Error when executing '#{hello_script} '. Response: Specify a name!\n", error.message)
    error = assert_raises(RuntimeError) { ocm.shell("#{hello_script} ", STDOUT) }
    assert_equal("Error when executing '#{hello_script} '. Response: ", error.message)
  end

  def test_generating_ocp_info
    options = { :token => "abc" }
    ocm = BushSlicer::OCM.new(options)
    result = ocm.generate_ocp_info('https://api.osd4-123.w95o.s1.foo.com:6443/', '{ "user": "guest", "password": "some-password" }')
    assert_equal('osd4-123.w95o.s1.foo.com', result["ocp_domain"])
    assert_equal('https://api.osd4-123.w95o.s1.foo.com:6443', result["ocp_api_url"])
    assert_equal('https://console-openshift-console.apps.osd4-123.w95o.s1.foo.com', result["ocp_console_url"])
    assert_equal('guest', result["user"])
    assert_equal('some-password', result["password"])
  end

end
