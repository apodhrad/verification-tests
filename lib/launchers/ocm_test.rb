puts BushSlicer::PRIVATE_DIR

ENV['BUSHSLICER_PRIVATE_DIR'] = nil
ENV['OCM_NAME'] = nil
ENV['OCM_TOKEN'] = nil
ENV['OCM_URL'] = nil
ENV['OCM_REGION'] = nil
ENV['OCM_VERSION'] = nil
ENV['OCM_LIFESPAN'] = nil

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
    assert_equal('{"name":"myosd4","managed":"true","multi_az":"false","byoc":"false"}', json)
  end

  def test_generating_json_with_region
    options = { :token => "abc", :region => "us-east-1" }
    ocm = BushSlicer::OCM.new(options)
    json = ocm.generate_json('myosd4')
    assert_equal('{"name":"myosd4","managed":"true","multi_az":"false","byoc":"false","region":{"id":"us-east-1"}}', json)
  end

  def test_generating_json_with_version
    options = { :token => "abc", :version => "4.6.1" }
    ocm = BushSlicer::OCM.new(options)
    json = ocm.generate_json('myosd4')
    assert_equal('{"name":"myosd4","managed":"true","multi_az":"false","byoc":"false","version":{"id":"openshift-v4.6.1"}}', json)
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

end
