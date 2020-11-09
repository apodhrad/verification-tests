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

require 'common'
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
    options = { :token => "abc", :lifespan => 25 }
    ocm = BushSlicer::OCM.new(options)
    json = ocm.generate_json('myosd4')
    time = Time.now + 60 * 60 * 25
    year = time.strftime("%Y")
    month = time.strftime("%m")
    day = time.strftime("%d")
    assert_match(/.*"expiration_timestamp":"#{year}-#{month}-#{day}T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z".*/, json)
  end

  def test_downloading_osd_script
    options = { :token => "abc" }
    ocm = BushSlicer::OCM.new(options)
    osd_script = ocm.download_osd_script
    assert(File.exists?("/tmp/osd-scripts/osd-provision.sh"), "File 'osd-provision.sh' was not downloaded")
    content = File.read("/tmp/osd-scripts/osd-provision.sh")
    assert_match(/.*ocm.*/, content)
  end

  #def test_downloading_osd_script_envvar
  #  custom_osd_script = Tempfile.new("custom-osd-script.sh", Host.localhost.workdir)
  #  custom_osd_script.write("ocm command --option value")
  #  options = { :token => "abc" }
  #  ocm = BushSlicer::OCM.new(options)
  #  osd_script = ocm.download_osd_script
  #  assert(File.exists?("/tmp/osd-scripts/osd-provision.sh"), "File 'osd-provision.sh' was not downloaded")
  #  content = File.read("/tmp/osd-scripts/osd-provision.sh")
  #  assert_match(/.*ocm.*/, content)
  #end

end
